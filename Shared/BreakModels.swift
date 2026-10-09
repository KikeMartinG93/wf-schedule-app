import Foundation
import SwiftUI
import WidgetKit

/// One break in the day: a time of day plus a length. The plan repeats every
/// day; "taken" only counts for the day it was marked, so it resets by itself.
struct BreakSlot: Codable, Identifiable, Equatable {
    var id = UUID()
    var minutesFromMidnight: Int
    var durationMinutes: Int
    var takenOn: Date?

    func dueDate(on day: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .minute, value: minutesFromMidnight, to: calendar.startOfDay(for: day)) ?? day
    }

    func isTaken(on day: Date) -> Bool {
        guard let takenOn else { return false }
        return Calendar.current.isDate(takenOn, inSameDayAs: day)
    }
}

struct BreakPlan: Codable, Equatable {
    var slots: [BreakSlot] = []

    /// Starting points modeled on a typical shift: 10 min, 30 min, 10 min.
    static func defaultSlot(index: Int) -> BreakSlot {
        let defaults: [(minutes: Int, length: Int)] = [(705, 10), (825, 30), (930, 10)]
        if index < defaults.count {
            return BreakSlot(minutesFromMidnight: defaults[index].minutes, durationMinutes: defaults[index].length)
        }
        return BreakSlot(minutesFromMidnight: min(930 + (index - 2) * 60, 1380), durationMinutes: 10)
    }
}

enum BreakStatus: Equatable {
    case none
    case allTaken
    case upcoming(due: Date, number: Int, duration: Int)
    case overdue(due: Date, number: Int, duration: Int)
}

extension BreakPlan {
    /// The earliest break not yet taken today: upcoming until its time, then
    /// overdue until it's marked taken.
    func status(at now: Date) -> BreakStatus {
        guard !slots.isEmpty else { return .none }
        let pending = slots.enumerated()
            .filter { !$0.element.isTaken(on: now) }
            .min { $0.element.minutesFromMidnight < $1.element.minutesFromMidnight }
        guard let pending else { return .allTaken }
        let due = pending.element.dueDate(on: now)
        let number = pending.offset + 1
        let duration = pending.element.durationMinutes
        return due > now
            ? .upcoming(due: due, number: number, duration: duration)
            : .overdue(due: due, number: number, duration: duration)
    }
}

/// Bar length follows the time left (full at two hours or more); the color
/// runs from green through amber to red over the last 45 minutes, and is solid
/// red once the break is overdue.
enum BreakStyle {
    static let greenHue = 0.33
    static let colorWindow: TimeInterval = 45 * 60
    static let fillWindow: TimeInterval = 120 * 60

    static func fill(remaining: TimeInterval) -> Double {
        min(max(remaining / fillWindow, 0.04), 1)
    }

    /// `nil` remaining means overdue.
    static func color(remaining: TimeInterval?) -> Color {
        // High contrast: no hue at all. Solid black/white once overdue, gray before.
        if ContrastPreference.high { return remaining == nil ? Color.primary : Color.gray }
        guard let remaining else { return Color(hue: 0, saturation: 0.85, brightness: 0.95) }
        let progress = min(max(remaining / colorWindow, 0), 1)
        return Color(hue: greenHue * progress, saturation: 0.85, brightness: 0.95)
    }
}

struct BreakBar: View {
    let fill: Double
    let color: Color

    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(0.2))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(color)
                    .scaleEffect(x: fill, y: 1, anchor: .leading)
            }
            .clipShape(Capsule())
    }
}

/// Stored in the shared app-group defaults so the iPhone widget can read it,
/// and mirrored to the watch by `BarcodePhoneSync`.
enum BreakStore {
    static let appGroupID = "group.com.marting.WFM"
    static let key = "breakPlanJSON"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    static var rawJSON: String? { defaults?.string(forKey: key) }

    static func load() -> BreakPlan {
        if let json = rawJSON, let data = json.data(using: .utf8),
           let plan = try? JSONDecoder().decode(BreakPlan.self, from: data),
           !plan.slots.isEmpty {
            return plan
        }
        if UserDefaults.standard.bool(forKey: "demoModeEnabled") {
            let calendar = Calendar.current
            let now = Date()
            let minuteOfDay = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
            return BreakPlan(slots: [
                BreakSlot(minutesFromMidnight: min(minuteOfDay + 35, 1420), durationMinutes: 15),
                BreakSlot(minutesFromMidnight: min(minuteOfDay + 120, 1425), durationMinutes: 30),
                BreakSlot(minutesFromMidnight: min(minuteOfDay + 240, 1430), durationMinutes: 15)
            ])
        }
        return BreakPlan()
    }

    /// Callers that save repeatedly (a time-picker wheel) pass `reloadWidgets: false`
    /// and reload once when the edits settle.
    static func save(_ plan: BreakPlan, reloadWidgets: Bool = true) {
        guard let data = try? JSONEncoder().encode(plan), let json = String(data: data, encoding: .utf8) else { return }
        defaults?.set(json, forKey: key)
        if reloadWidgets { WidgetCenter.shared.reloadAllTimelines() }
    }
}
