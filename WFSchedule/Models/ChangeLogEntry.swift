import Foundation

/// A persisted record of one detected schedule change, for the Alerts tab.
///
/// UKG's own data has no concept of "this shift was swapped with coworker X" —
/// `regularShifts`/`transferShifts` only ever describe YOUR shifts, never who
/// else might be involved in a change. So a swap can't be detected or
/// attributed automatically; instead, `swapNote` is a free-text field the user
/// fills in themselves from AlertsView when they know a change was a swap and
/// with whom — asking on a text field, since the API simply doesn't have it.
struct ChangeLogEntry: Codable, Identifiable {
    enum Kind: String, Codable {
        case new, changed, removed
    }

    let id: UUID
    let timestamp: Date
    let kind: Kind
    /// The current/new version of the shift (for `.removed`, the shift as it
    /// last existed).
    let shift: Shift
    /// Only set for `.changed` — what the shift looked like before.
    let previousShift: Shift?
    var swapNote: String?
    /// Whether the user has dismissed/acknowledged this alert. Read-modify-set
    /// from AlertsView's "mark as seen" button; a seen entry renders in a
    /// compact layout instead of the full detail card.
    var seen: Bool = false

    init(timestamp: Date, kind: Kind, shift: Shift, previousShift: Shift? = nil, swapNote: String? = nil, seen: Bool = false) {
        self.id = UUID()
        self.timestamp = timestamp
        self.kind = kind
        self.shift = shift
        self.previousShift = previousShift
        self.swapNote = swapNote
        self.seen = seen
    }

    init(change: ScheduleChangeKind, timestamp: Date = Date()) {
        switch change {
        case .new(let shift):
            self.init(timestamp: timestamp, kind: .new, shift: shift)
        case .changed(let old, let new):
            self.init(timestamp: timestamp, kind: .changed, shift: new, previousShift: old)
        case .removed(let shift):
            self.init(timestamp: timestamp, kind: .removed, shift: shift)
        }
    }

    /// Custom decode so existing `change_log.json` files written before
    /// `seen` existed don't fail to decode wholesale (JSONDecoder's
    /// synthesized init would require the key to be present) — missing means
    /// not-yet-seen, same as any entry logged before this feature existed.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        kind = try container.decode(Kind.self, forKey: .kind)
        shift = try container.decode(Shift.self, forKey: .shift)
        previousShift = try container.decodeIfPresent(Shift.self, forKey: .previousShift)
        swapNote = try container.decodeIfPresent(String.self, forKey: .swapNote)
        seen = try container.decodeIfPresent(Bool.self, forKey: .seen) ?? false
    }

    /// Human-readable description of what happened, used directly in AlertsView.
    var summary: String {
        switch kind {
        case .new:
            return String(localized: "New shift added")
        case .removed:
            return String(localized: "Shift removed from your schedule")
        case .changed:
            guard let previousShift else { return String(localized: "Shift details updated") }
            return shift.changeDescription(from: previousShift)
        }
    }
}

extension Shift {
    /// Field-by-field diff against a previous version of the same shift,
    /// joined into one readable sentence — e.g. "Time changed from 8:00 AM–
    /// 4:00 PM to 9:00 AM–5:00 PM; Location changed from GIL-10530 to GIL-20044".
    func changeDescription(from old: Shift) -> String {
        var parts: [String] = []
        let timeFormatter: (Date) -> String = { $0.formatted(date: .omitted, time: .shortened) }

        if old.startTime != startTime || old.endTime != endTime {
            parts.append(String(localized: "Time changed from \(timeFormatter(old.startTime))–\(timeFormatter(old.endTime)) to \(timeFormatter(startTime))–\(timeFormatter(endTime))"))
        }
        if old.job != job {
            parts.append(String(localized: "Job changed from \(old.job) to \(job)"))
        }
        if old.location != location {
            parts.append(String(localized: "Location changed from \(old.location ?? "—") to \(location ?? "—")"))
        }
        if old.kind != kind {
            parts.append(String(localized: "Type changed from \(old.kind.displayName) to \(kind.displayName)"))
        }
        return parts.isEmpty ? String(localized: "Shift details updated") : parts.joined(separator: "; ")
    }
}
