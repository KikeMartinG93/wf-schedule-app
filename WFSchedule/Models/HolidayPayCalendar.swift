import Foundation

/// Dates Whole Foods pays a premium if you work them — time-and-a-half for
/// New Year's Day, Easter, Memorial Day, Independence Day, and Labor Day;
/// double time for Thanksgiving. Sourced from publicly reported Whole Foods
/// employee benefits info (Glassdoor/Indeed), not an official published
/// list — there's no public API for this. Easter, Memorial Day, Labor Day,
/// and Thanksgiving move every year, so these are computed rather than
/// hardcoded to a single year.
enum HolidayPayCalendar {
    /// The calendar grid asks about every visible day on every redraw, and each
    /// answer needs Easter and several weekday searches — so results are kept per
    /// year (the set is a handful of dates) instead of recomputed each time.
    private static let cacheLock = NSLock()
    private static var cache: [Int: Set<Date>] = [:]

    static func holidays(for year: Int) -> Set<Date> {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cache[year] { return cached }
        let computed = computeHolidays(for: year)
        cache[year] = computed
        return computed
    }

    private static func computeHolidays(for year: Int) -> Set<Date> {
        let calendar = Calendar.current

        func date(month: Int, day: Int) -> Date? {
            calendar.date(from: DateComponents(year: year, month: month, day: day))
        }

        let dates: [Date?] = [
            date(month: 1, day: 1),                                    // New Year's Day
            calendar.date(from: easter(year: year)),                   // Easter
            lastWeekday(2, ofMonth: 5, year: year, calendar: calendar), // Memorial Day
            date(month: 7, day: 4),                                    // Independence Day
            nthWeekday(1, weekday: 2, ofMonth: 9, year: year, calendar: calendar),  // Labor Day
            nthWeekday(4, weekday: 5, ofMonth: 11, year: year, calendar: calendar), // Thanksgiving
        ]

        return Set(dates.compactMap { $0.map { calendar.startOfDay(for: $0) } })
    }

    /// Anonymous Gregorian algorithm (Meeus/Jones/Butcher).
    private static func easter(year: Int) -> DateComponents {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return DateComponents(year: year, month: month, day: day)
    }

    /// `weekday` uses Foundation's convention: 1 = Sunday ... 7 = Saturday.
    private static func nthWeekday(_ n: Int, weekday: Int, ofMonth month: Int, year: Int, calendar: Calendar) -> Date? {
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
        let firstWeekday = calendar.component(.weekday, from: first)
        let offset = (weekday - firstWeekday + 7) % 7
        let day = 1 + offset + (n - 1) * 7
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func lastWeekday(_ weekday: Int, ofMonth month: Int, year: Int, calendar: Calendar) -> Date? {
        guard let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else { return nil }
        for day in stride(from: range.upperBound - 1, through: range.lowerBound, by: -1) {
            if let d = calendar.date(from: DateComponents(year: year, month: month, day: day)),
               calendar.component(.weekday, from: d) == weekday {
                return d
            }
        }
        return nil
    }
}
