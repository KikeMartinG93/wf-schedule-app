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

    init(ukgRecordId: String?, date: Date, startTime: Date, endTime: Date, job: String,
         location: String?, kind: ShiftKind, payCode: String?, notes: String?) {
        self.ukgRecordId = ukgRecordId
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.job = job
        self.location = location
        self.kind = kind
        self.payCode = payCode
        self.notes = notes
        self.id = Shift.matchKey(date: date, startTime: startTime, endTime: endTime, job: job)
    }
}

struct ScheduleSnapshot: Codable {
    var fetchedAt: Date
    var shifts: [Shift]
    /// Match keys missing from the most recent fetch but not yet confirmed removed
    /// (needs to be missing twice in a row before we treat it as an actual removal).
    var pendingRemovalMisses: [String: Int]
}
