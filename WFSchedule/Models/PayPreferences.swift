import Foundation
import SwiftUI

/// How the associate receives their Whole Foods paycheck.
enum PaymentMethod: String, CaseIterable, Identifiable {
    case directDeposit
    case check

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .directDeposit: "Direct Deposit"
        case .check: "Check"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .directDeposit: "Paid every other week by bank deposit."
        case .check: "Paid by paper check — no payday markers."
        }
    }
}

/// Weekday Whole Foods Direct Deposit lands for this store / associate.
enum PaydayWeekday: String, CaseIterable, Identifiable {
    case wednesday
    case friday

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .wednesday: "Wednesdays"
        case .friday: "Fridays"
        }
    }

    /// Foundation weekday: 1 = Sunday … 7 = Saturday.
    var calendarWeekday: Int {
        switch self {
        case .wednesday: 4
        case .friday: 6
        }
    }

    /// Known upcoming payday used as the biweekly anchor (Nov 2026).
    /// Wed → 11/11/2026, Fri → 11/13/2026. Pay period for both is 10/26–11/08.
    var anchorPayday: Date {
        let calendar = Calendar.current
        switch self {
        case .wednesday:
            return calendar.date(from: DateComponents(year: 2026, month: 11, day: 11))!
        case .friday:
            return calendar.date(from: DateComponents(year: 2026, month: 11, day: 13))!
        }
    }
}

/// Persisted pay setup from onboarding / Settings. Direct Deposit + weekday
/// turns on biweekly Payday markers in the app and on the Work Schedule calendar.
enum PayPreferences {
    private static let methodKey = "payPaymentMethod"
    private static let weekdayKey = "payPaydayWeekday"
    private static let configuredKey = "payPreferencesConfigured"

    static var isConfigured: Bool {
        UserDefaults.standard.bool(forKey: configuredKey)
    }

    static var method: PaymentMethod? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: methodKey) else { return nil }
            return PaymentMethod(rawValue: raw)
        }
        set {
            UserDefaults.standard.set(newValue?.rawValue, forKey: methodKey)
        }
    }

    static var weekday: PaydayWeekday? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: weekdayKey) else { return nil }
            return PaydayWeekday(rawValue: raw)
        }
        set {
            UserDefaults.standard.set(newValue?.rawValue, forKey: weekdayKey)
        }
    }

    /// Direct Deposit with a chosen weekday — the only mode that shows Payday.
    static var showsPayday: Bool {
        method == .directDeposit && weekday != nil
    }

    static func save(method: PaymentMethod, weekday: PaydayWeekday?) {
        self.method = method
        if method == .directDeposit {
            self.weekday = weekday
        } else {
            self.weekday = nil
        }
        UserDefaults.standard.set(true, forKey: configuredKey)
        NotificationCenter.default.post(name: .payPreferencesDidChange, object: nil)
    }

    /// User skipped pay questions — don’t keep re-prompting, but leave method unset.
    static func markSkipped() {
        UserDefaults.standard.set(true, forKey: configuredKey)
        NotificationCenter.default.post(name: .payPreferencesDidChange, object: nil)
    }
}

extension Notification.Name {
    static let payPreferencesDidChange = Notification.Name("PayPreferencesDidChange")
}

/// Biweekly Whole Foods Direct Deposit dates, anchored to the known Nov 2026
/// payday the user picked (Wed 11/11 or Fri 11/13).
enum PaydayCalendar {
    private static let biweeklyDays = 14

    static func isPayday(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard PayPreferences.showsPayday, let weekday = PayPreferences.weekday else { return false }
        let day = calendar.startOfDay(for: date)
        let anchor = calendar.startOfDay(for: weekday.anchorPayday)
        let delta = calendar.dateComponents([.day], from: anchor, to: day).day ?? 0
        return delta % biweeklyDays == 0
    }

    /// Paydays from `start` through `end` (inclusive), empty if payday is off.
    static func paydays(from start: Date, through end: Date, calendar: Calendar = .current) -> [Date] {
        guard PayPreferences.showsPayday, let weekday = PayPreferences.weekday else { return [] }
        let rangeStart = calendar.startOfDay(for: start)
        let rangeEnd = calendar.startOfDay(for: end)
        let anchor = calendar.startOfDay(for: weekday.anchorPayday)

        var cursor = anchor
        while cursor > rangeStart {
            guard let prev = calendar.date(byAdding: .day, value: -biweeklyDays, to: cursor) else { break }
            cursor = prev
        }
        if cursor < rangeStart {
            while cursor < rangeStart {
                guard let next = calendar.date(byAdding: .day, value: biweeklyDays, to: cursor) else { break }
                cursor = next
            }
        }

        var dates: [Date] = []
        while cursor <= rangeEnd {
            dates.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: biweeklyDays, to: cursor) else { break }
            cursor = next
        }
        return dates
    }

    /// The Mon–Sun two-week period paid on `payday` (e.g. 10/26–11/08 for 11/11 or 11/13).
    static func payPeriod(forPayday payday: Date, calendar: Calendar = .current) -> (start: Date, end: Date)? {
        // US weeks start Sunday: start of the week containing payday is that Sunday,
        // which is also the period end for the prior two-week block.
        var cal = calendar
        cal.firstWeekday = 1
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: payday)?.start else { return nil }
        let periodEnd = cal.startOfDay(for: weekStart)
        guard let periodStart = cal.date(byAdding: .day, value: -13, to: periodEnd) else { return nil }
        return (periodStart, periodEnd)
    }

    static func periodDescription(forPayday payday: Date, calendar: Calendar = .current) -> String? {
        guard let period = payPeriod(forPayday: payday, calendar: calendar) else { return nil }
        let style = Date.FormatStyle().month(.defaultDigits).day().year(.twoDigits)
        return "\(period.start.formatted(style)) – \(period.end.formatted(style))"
    }
}
