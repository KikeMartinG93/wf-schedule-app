import Foundation

enum ShiftKind: String, Codable {
    case regular
    case payCodeChange
    case transfer
    case holiday
    case timeOff

    var displayName: String {
        switch self {
        case .regular: String(localized: "Regular")
        case .payCodeChange: String(localized: "Pay code change")
        case .transfer: String(localized: "Transfer")
        case .holiday: String(localized: "Holiday")
        case .timeOff: String(localized: "Time off")
        }
    }
}

struct Shift: Codable, Identifiable, Equatable {
    /// Stable identity derived from date+start+end+job, NOT the UKG record id/version.
    /// UKG reassigns internal ids/versions on minor edits; keying on those would create
    /// spurious "new shift" / "removed shift" pairs for what is really the same shift.
    var id: String
    var ukgRecordId: String?
    var date: Date
    var startTime: Date
    var endTime: Date
    var job: String
    var location: String?
    var kind: ShiftKind
    var payCode: String?
    var notes: String?

    static func matchKey(date: Date, startTime: Date, endTime: Date, job: String) -> String {
        let df = ISO8601DateFormatter()
        return [df.string(from: date), df.string(from: startTime), df.string(from: endTime), job]
            .joined(separator: "|")
    }

    /// Supervisor shifts starting at 6:00 am or 7:00 am are labeled as "Cash Office".
    static func normalizeJob(_ job: String, startTime: Date, calendar: Calendar = .current) -> String {
        if job.caseInsensitiveCompare("Supervisor") == .orderedSame {
            let components = calendar.dateComponents([.hour, .minute], from: startTime)
            if let hour = components.hour, let minute = components.minute {
                if (hour == 6 && minute == 0) || (hour == 7 && minute == 0) {
                    return "Cash Office"
                }
            }
        }
        return job
    }

    /// Normalizes store location codes (e.g. UKG's "GIL-10530") to friendly store names (e.g. "Gilman"),
    /// preventing false "Location changed" diffs when switching between UKG and Innerview.
    static func normalizeLocation(_ location: String?) -> String? {
        guard let location = location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty else { return nil }
        let upper = location.uppercased()
        if upper == "GIL-10530" || upper.hasPrefix("GIL-") {
            return "Gilman"
        }
        return location
    }

    init(ukgRecordId: String?, date: Date, startTime: Date, endTime: Date, job: String,
         location: String?, kind: ShiftKind, payCode: String?, notes: String?) {
        self.ukgRecordId = ukgRecordId
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        let normalizedJob = Shift.normalizeJob(job, startTime: startTime)
        self.job = normalizedJob
        self.location = Shift.normalizeLocation(location)
        self.kind = kind
        self.payCode = payCode
        self.notes = notes
        self.id = Shift.matchKey(date: date, startTime: startTime, endTime: endTime, job: normalizedJob)
    }

    enum CodingKeys: String, CodingKey {
        case id, ukgRecordId, date, startTime, endTime, job, location, kind, payCode, notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let ukgRecordId = try container.decodeIfPresent(String.self, forKey: .ukgRecordId)
        let date = try container.decode(Date.self, forKey: .date)
        let startTime = try container.decode(Date.self, forKey: .startTime)
        let endTime = try container.decode(Date.self, forKey: .endTime)
        let rawJob = try container.decode(String.self, forKey: .job)
        let rawLocation = try container.decodeIfPresent(String.self, forKey: .location)
        let kind = try container.decode(ShiftKind.self, forKey: .kind)
        let payCode = try container.decodeIfPresent(String.self, forKey: .payCode)
        let notes = try container.decodeIfPresent(String.self, forKey: .notes)

        self.init(
            ukgRecordId: ukgRecordId,
            date: date,
            startTime: startTime,
            endTime: endTime,
            job: rawJob,
            location: rawLocation,
            kind: kind,
            payCode: payCode,
            notes: notes
        )
    }
}

struct ScheduleSnapshot: Codable {
    var fetchedAt: Date
    var shifts: [Shift]
    /// Match keys missing from the most recent fetch but not yet confirmed removed
    /// (needs to be missing twice in a row before we treat it as an actual removal).
    var pendingRemovalMisses: [String: Int]
}
