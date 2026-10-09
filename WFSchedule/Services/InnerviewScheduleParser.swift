import Foundation

/// Turns the plain text of Innerview's week view (`document.body.innerText`)
/// into shifts.
///
/// Confirmed against the live page: each day is a header line ("Thursday,
/// Sep 24", or "(Today) Wednesday, Sep 23"), then either "No scheduled shifts"
/// or, per shift, four lines — start time, end time, location, "Team, Job".
/// Week-range headers like "(Sep 28 - Oct 4)" sit between weeks, and a day that
/// has been expanded adds a "SHIFT DETAILS" block of per-segment times and
/// breaks that this ignores (breaks here are the user's own, set in the app).
///
/// Reading the rendered text rather than Innerview's private JSON API is
/// deliberate: the API's request body isn't documented and isn't visible in
/// Safari's inspector, while the page's text has stayed a simple, stable shape.
/// The headers carry no year, so it's inferred as whichever year lands that
/// month and day (with a matching weekday) nearest to now.
enum InnerviewScheduleParser {
    struct Result {
        /// How many day headers were seen — zero means the page wasn't the
        /// schedule at all (still loading, or a sign-in page), as opposed to a
        /// schedule with no shifts on it.
        var dayCount: Int
        var shifts: [Shift]
    }

    static func parse(pageText: String, now: Date = Date(), calendar: Calendar = .current) -> Result {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let today = gregorian.startOfDay(for: now)

        let lines = pageText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var shifts: [Shift] = []
        var seenIDs = Set<String>()
        var dayCount = 0
        var currentDay: Date?
        var inDetails = false
        var index = 0

        while index < lines.count {
            let line = lines[index]

            if let header = parseDayHeader(line) {
                dayCount += 1
                inDetails = false
                currentDay = resolveDate(month: header.month, day: header.day, weekday: header.weekday, now: now, calendar: gregorian)
                index += 1
                continue
            }
            if isWeekRangeHeader(line) || equals(line, "This Week") {
                inDetails = false
                index += 1
                continue
            }
            if equals(line, "SHIFT DETAILS") {
                inDetails = true
                index += 1
                continue
            }
            guard let day = currentDay, !inDetails,
                  let start = parseTime(line),
                  index + 1 < lines.count, let end = parseTime(lines[index + 1]) else {
                index += 1
                continue
            }

            var next = index + 2
            var location: String?
            var job: String?
            if next < lines.count, !isStructural(lines[next]) {
                location = lines[next]
                next += 1
            }
            if next < lines.count, !isStructural(lines[next]) {
                job = lines[next]
                next += 1
            }

            if let startTime = time(start, on: day, calendar: gregorian),
               var endTime = time(end, on: day, calendar: gregorian) {
                if endTime <= startTime {
                    endTime = gregorian.date(byAdding: .day, value: 1, to: endTime) ?? endTime
                }
                if day >= today {
                    let shift = Shift(
                        ukgRecordId: nil,
                        date: day,
                        startTime: startTime,
                        endTime: endTime,
                        job: displayName(forJob: job) ?? "Shift",
                        location: location,
                        kind: .regular,
                        payCode: nil,
                        notes: nil
                    )
                    if seenIDs.insert(shift.id).inserted { shifts.append(shift) }
                }
            }
            index = next
        }

        return Result(dayCount: dayCount, shifts: shifts.sorted { $0.startTime < $1.startTime })
    }

    /// Innerview doesn't show the role, only "Team, Job" — and Customer Service
    /// Front End is the Supervisor position, so it's shown as that (which is also
    /// what gives it the Supervisor color).
    private static let jobNames = ["customer service team, front end": "Supervisor"]

    private static func displayName(forJob job: String?) -> String? {
        guard let job else { return nil }
        return jobNames[job.lowercased()] ?? job
    }

    // MARK: - Lines

    private static let dayHeaderPattern = try! NSRegularExpression(
        pattern: #"^(?:\(Today\)\s*)?([A-Za-z]{3,9}),\s*([A-Za-z]{3,9})\s+(\d{1,2})$"#
    )
    private static let timePattern = try! NSRegularExpression(
        pattern: #"^(\d{1,2}):(\d{2})\s*([AaPp][Mm])$"#
    )

    private static let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                                 "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]
    /// Gregorian numbering: Sunday is 1.
    private static let weekdays = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]

    private struct DayHeader {
        var month: Int
        var day: Int
        var weekday: Int?
    }

    private struct ClockTime {
        var hour: Int
        var minute: Int
    }

    private static func parseDayHeader(_ line: String) -> DayHeader? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = dayHeaderPattern.firstMatch(in: line, range: range),
              let weekdayRange = Range(match.range(at: 1), in: line),
              let monthRange = Range(match.range(at: 2), in: line),
              let dayRange = Range(match.range(at: 3), in: line),
              let month = months[String(line[monthRange].prefix(3)).lowercased()],
              let weekday = weekdays[String(line[weekdayRange].prefix(3)).lowercased()],
              let day = Int(line[dayRange]) else { return nil }
        return DayHeader(month: month, day: day, weekday: weekday)
    }

    private static func parseTime(_ line: String) -> ClockTime? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = timePattern.firstMatch(in: line, range: range),
              let hourRange = Range(match.range(at: 1), in: line),
              let minuteRange = Range(match.range(at: 2), in: line),
              let meridiemRange = Range(match.range(at: 3), in: line),
              var hour = Int(line[hourRange]), let minute = Int(line[minuteRange]),
              (1...12).contains(hour), (0...59).contains(minute) else { return nil }
        let isPM = line[meridiemRange].lowercased() == "pm"
        if hour == 12 { hour = 0 }
        if isPM { hour += 12 }
        return ClockTime(hour: hour, minute: minute)
    }

    private static func isWeekRangeHeader(_ line: String) -> Bool {
        line.hasPrefix("(") && line.hasSuffix(")") && line.contains(" - ")
    }

    private static func equals(_ line: String, _ marker: String) -> Bool {
        line.caseInsensitiveCompare(marker) == .orderedSame
    }

    /// A line that can't be a location or a job, so a shift block ends there.
    private static func isStructural(_ line: String) -> Bool {
        parseDayHeader(line) != nil
            || parseTime(line) != nil
            || isWeekRangeHeader(line)
            || ["This Week", "No scheduled shifts", "SHIFT DETAILS", "PUNCH TIMES",
                "No punch data is available", "View More", "Break"].contains { equals(line, $0) }
    }

    // MARK: - Dates

    private static func resolveDate(month: Int, day: Int, weekday: Int?, now: Date, calendar: Calendar) -> Date? {
        let currentYear = calendar.component(.year, from: now)
        func nearest(requireWeekday: Bool) -> Date? {
            var best: (date: Date, distance: TimeInterval)?
            for year in [currentYear - 1, currentYear, currentYear + 1] {
                var components = DateComponents()
                components.year = year
                components.month = month
                components.day = day
                guard let date = calendar.date(from: components),
                      calendar.component(.month, from: date) == month else { continue }
                if requireWeekday, let weekday, calendar.component(.weekday, from: date) != weekday { continue }
                let distance = abs(date.timeIntervalSince(now))
                if best == nil || distance < best!.distance { best = (date, distance) }
            }
            return best?.date
        }
        return nearest(requireWeekday: true) ?? nearest(requireWeekday: false)
    }

    private static func time(_ clock: ClockTime, on day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: day)
    }
}
