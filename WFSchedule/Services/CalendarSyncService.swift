import Foundation
import EventKit

enum CalendarSyncError: LocalizedError {
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .accessDenied: String(localized: "Calendar access was not granted.")
        }
    }
}

/// Maintains a dedicated "Work Schedule" Apple Calendar and keeps it in sync with
/// detected shift changes. Only ever touches events it created itself (tracked by
/// storing the Shift's match-key id in the event's notes as a hidden marker), and
/// never modifies the user's other calendars.
final class CalendarSyncService {
    static let calendarTitle = "Work Schedule"
    private static let markerPrefix = "wfschedule-id:"

    private let store = EKEventStore()

    func requestAccess() async throws {
        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = try await store.requestFullAccessToEvents()
        } else {
            granted = try await withCheckedThrowingContinuation { cont in
                store.requestAccess(to: .event) { ok, error in
                    if let error { cont.resume(throwing: error) } else { cont.resume(returning: ok) }
                }
            }
        }
        guard granted else { throw CalendarSyncError.accessDenied }
    }

    private func workScheduleCalendar() -> EKCalendar {
        if let existing = store.calendars(for: .event).first(where: { $0.title == Self.calendarTitle }) {
            return existing
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = Self.calendarTitle
        calendar.source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first(where: { $0.sourceType == .local })
        try? store.saveCalendar(calendar, commit: true)
        return calendar
    }

    private func marker(for shiftId: String) -> String {
        Self.markerPrefix + shiftId
    }

    /// All events already tracking this shift (its marker in the notes field),
    /// not just the first — a plain uninstall wipes this app's own on-disk
    /// schedule snapshot (`ScheduleStore`, in the app's sandbox) but NOT this
    /// calendar (a separate system database), so the first sync after a
    /// reinstall has no "previous" snapshot to diff against and used to treat
    /// every shift as brand new, creating a duplicate event for each one
    /// already here. Returning every match (instead of just one) is what lets
    /// callers actually find and clean those up.
    private func existingEvents(for shiftId: String, in calendar: EKCalendar) -> [EKEvent] {
        // Search a wide window since shifts can be scheduled well into the future.
        let start = Date().addingTimeInterval(-86_400 * 400)
        let end = Date().addingTimeInterval(86_400 * 400)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])
        return store.events(matching: predicate).filter { $0.notes?.contains(marker(for: shiftId)) == true }
    }

    private func existingEvent(for shiftId: String, in calendar: EKCalendar) -> EKEvent? {
        existingEvents(for: shiftId, in: calendar).first
    }

    func apply(changes: [ScheduleChangeKind]) throws {
        let calendar = workScheduleCalendar()

        for change in changes {
            switch change {
            case .new(let shift):
                // Nothing should exist under its own id yet, but if a sync
                // somehow ran twice this is harmlessly idempotent — same as
                // finding one already there and updating it in place.
                try upsert(shift, matchingEventFor: shift.id, in: calendar)

            case .changed(let old, let new):
                // A shift's id is derived from date+start+end+job (see
                // `Shift.matchKey`), so an edited shift has a DIFFERENT id
                // than the event already sitting on the calendar for it —
                // that event is still tagged with `old.id`. Matching on the
                // old id here, not the new shift's own id, is what makes
                // this a true in-place edit of that same event (re-tagged
                // with the new id via `configure`) instead of leaving the
                // old event behind while a second one gets created.
                try upsert(new, matchingEventFor: old.id, in: calendar)

            case .removed(let shift):
                for event in existingEvents(for: shift.id, in: calendar) {
                    try store.remove(event, span: .thisEvent)
                }
            }
        }

        try store.commit()
    }

    private func upsert(_ shift: Shift, matchingEventFor existingId: String, in calendar: EKCalendar) throws {
        if let event = existingEvent(for: existingId, in: calendar) {
            configure(event, with: shift, calendar: calendar)
            try store.save(event, span: .thisEvent)
        } else {
            let event = EKEvent(eventStore: store)
            configure(event, with: shift, calendar: calendar)
            try store.save(event, span: .thisEvent)
        }
    }

    /// Collapses any shift that ended up with more than one event (from past
    /// reinstalls, before the upsert-on-`.new` fix above existed) down to
    /// one, keeping whichever copy was modified most recently. Cheap to run
    /// every sync since it's scoped to just this one calendar.
    func deduplicateEvents() throws {
        let calendar = workScheduleCalendar()
        let start = Date().addingTimeInterval(-86_400 * 400)
        let end = Date().addingTimeInterval(86_400 * 400)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])

        var byMarker: [String: [EKEvent]] = [:]
        for event in store.events(matching: predicate) {
            guard let notes = event.notes, let range = notes.range(of: Self.markerPrefix) else { continue }
            let shiftId = notes[range.upperBound...].prefix { $0 != "\n" }
            byMarker[String(shiftId), default: []].append(event)
        }

        var didChange = false
        for group in byMarker.values where group.count > 1 {
            let newestFirst = group.sorted { ($0.lastModifiedDate ?? .distantPast) > ($1.lastModifiedDate ?? .distantPast) }
            for stale in newestFirst.dropFirst() {
                try store.remove(stale, span: .thisEvent)
                didChange = true
            }
        }
        if didChange {
            try store.commit()
        }
    }

    /// Re-applies current formatting (title, location, notes) to every already-
    /// synced event, even for shifts `ScheduleDiffer` didn't flag as changed.
    /// The diff only compares `Shift`'s own fields — it has no way to know when
    /// this service's own formatting changes (e.g. dropping "— Regular" from
    /// titles), so an event synced before such a change would otherwise never
    /// get corrected. Only writes when something's actually different.
    func reconcileTitles(for shifts: [Shift]) throws {
        let calendar = workScheduleCalendar()
        var didChange = false
        for shift in shifts {
            for event in existingEvents(for: shift.id, in: calendar) {
                if event.title != shift.job || event.location != shift.location {
                    configure(event, with: shift, calendar: calendar)
                    try store.save(event, span: .thisEvent)
                    didChange = true
                }
            }
        }
        if didChange {
            try store.commit()
        }
    }

    private func configure(_ event: EKEvent, with shift: Shift, calendar: EKCalendar) {
        event.calendar = calendar
        event.title = shift.job
        event.startDate = shift.startTime
        event.endDate = shift.endTime
        event.location = shift.location
        var notes = marker(for: shift.id)
        if let payCode = shift.payCode { notes += "\npay code: \(payCode)" }
        if let extra = shift.notes { notes += "\n\(extra)" }
        event.notes = notes
    }
}
