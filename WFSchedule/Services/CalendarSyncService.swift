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

    /// All events matching a shift by ID marker, legacy Supervisor marker (for Cash Office shifts),
    /// or matching start/end date/time on the Work Schedule calendar.
    private func existingEvents(for shiftId: String, in calendar: EKCalendar) -> [EKEvent] {
        let start = Date().addingTimeInterval(-86_400 * 400)
        let end = Date().addingTimeInterval(86_400 * 400)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])
        return store.events(matching: predicate).filter { $0.notes?.contains(marker(for: shiftId)) == true }
    }

    private func existingEvents(for shift: Shift, in calendar: EKCalendar) -> [EKEvent] {
        let exactIdMatches = existingEvents(for: shift.id, in: calendar)
        if !exactIdMatches.isEmpty {
            return exactIdMatches
        }

        // Check legacy Supervisor shift ID marker if shift is now Cash Office
        if shift.job == "Cash Office" {
            let legacyId = Shift.matchKey(date: shift.date, startTime: shift.startTime, endTime: shift.endTime, job: "Supervisor")
            let legacyMatches = existingEvents(for: legacyId, in: calendar)
            if !legacyMatches.isEmpty {
                return legacyMatches
            }
        }

        // Fallback: search for an event on the Work Schedule calendar at the exact start & end time
        let predicate = store.predicateForEvents(withStart: shift.startTime, end: shift.endTime, calendars: [calendar])
        return store.events(matching: predicate).filter { event in
            abs(event.startDate.timeIntervalSince(shift.startTime)) < 60 &&
            abs(event.endDate.timeIntervalSince(shift.endTime)) < 60
        }
    }

    private func existingEvent(for shift: Shift, in calendar: EKCalendar) -> EKEvent? {
        existingEvents(for: shift, in: calendar).first
    }

    func apply(changes: [ScheduleChangeKind]) throws {
        let calendar = workScheduleCalendar()

        for change in changes {
            switch change {
            case .new(let shift):
                try upsert(shift, matchingEventFor: shift, in: calendar)

            case .changed(let old, let new):
                try upsert(new, matchingEventFor: old, in: calendar)

            case .removed(let shift):
                for event in existingEvents(for: shift, in: calendar) {
                    try store.remove(event, span: .thisEvent)
                }
            }
        }

        try store.commit()
    }

    private func upsert(_ shift: Shift, matchingEventFor target: Shift, in calendar: EKCalendar) throws {
        if let event = existingEvent(for: target, in: calendar) {
            configure(event, with: shift, calendar: calendar)
            try store.save(event, span: .thisEvent)
        } else {
            let event = EKEvent(eventStore: store)
            configure(event, with: shift, calendar: calendar)
            try store.save(event, span: .thisEvent)
        }
    }

    /// Collapses any shift that ended up with more than one event (from past
    /// reinstalls, before the upsert-on-`.new` fix existed) down to
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
    /// this service's own formatting changes (e.g. Supervisor -> Cash Office relabeling),
    /// so an event synced before such a change is updated here. Only writes when something's actually different.
    func reconcileTitles(for shifts: [Shift]) throws {
        let calendar = workScheduleCalendar()
        let start = Date().addingTimeInterval(-86_400 * 400)
        let end = Date().addingTimeInterval(86_400 * 400)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: [calendar])
        let allEvents = store.events(matching: predicate)

        var byMarker: [String: [EKEvent]] = [:]
        for event in allEvents {
            guard let notes = event.notes, let range = notes.range(of: Self.markerPrefix) else { continue }
            let shiftId = notes[range.upperBound...].prefix { $0 != "\n" }
            byMarker[String(shiftId), default: []].append(event)
        }

        var didChange = false
        for shift in shifts {
            var matchedEvents = byMarker[shift.id] ?? []
            if matchedEvents.isEmpty && shift.job == "Cash Office" {
                let legacyId = Shift.matchKey(date: shift.date, startTime: shift.startTime, endTime: shift.endTime, job: "Supervisor")
                matchedEvents = byMarker[legacyId] ?? []
            }
            if matchedEvents.isEmpty {
                matchedEvents = allEvents.filter { event in
                    abs(event.startDate.timeIntervalSince(shift.startTime)) < 60 &&
                    abs(event.endDate.timeIntervalSince(shift.endTime)) < 60
                }
            }

            for event in matchedEvents {
                let currentMarker = marker(for: shift.id)
                let needsUpdate = event.title != shift.job ||
                                 event.location != shift.location ||
                                 event.notes?.contains(currentMarker) == false
                if needsUpdate {
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
