import Foundation

/// The bare minimum of a shift the watch needs to run its countdown: when it
/// starts, when it ends, and what it is. The phone sends the upcoming ones over
/// WatchConnectivity; the watch never talks to UKG.
struct WatchShift: Codable, Equatable {
    var start: Date
    var end: Date
    var job: String
}

enum WatchShifts {
    static func encode(_ shifts: [WatchShift]) -> String {
        guard let data = try? JSONEncoder().encode(shifts), let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }

    static func decode(_ json: String?) -> [WatchShift] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([WatchShift].self, from: data)) ?? []
    }
}

/// What the countdown is showing at a given moment.
enum ShiftClockState: Equatable {
    /// A shift is happening now.
    case onShift(start: Date, end: Date)
    /// Nothing right now; the next shift starts at `start`.
    case upcoming(start: Date)
    case none

    static func state(at date: Date, shifts: [WatchShift]) -> ShiftClockState {
        if let current = shifts.filter({ $0.start <= date && date < $0.end }).max(by: { $0.end < $1.end }) {
            return .onShift(start: current.start, end: current.end)
        }
        if let next = shifts.filter({ $0.start > date }).min(by: { $0.start < $1.start }) {
            return .upcoming(start: next.start)
        }
        return .none
    }

    /// 0...1 through the current shift; 0 when not on shift.
    static func progress(start: Date, end: Date, now: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return min(max(now.timeIntervalSince(start) / total, 0), 1)
    }
}
