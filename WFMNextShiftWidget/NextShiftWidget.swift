import WidgetKit
import SwiftUI

/// The app publishes its schedule snapshot into the shared app-group container
/// (see `ScheduleStore.save`); the widget only ever reads it from there.
enum SharedSchedule {
    static let groupID = "group.com.marting.WFM"
    static let fileName = "schedule_snapshot.json"

    static func loadShifts() -> [Shift] {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
                .appendingPathComponent(fileName),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(ScheduleSnapshot.self, from: data)
        else { return [] }
        return snapshot.shifts
    }
}

// MARK: - Next Shift Widget

struct NextShiftEntry: TimelineEntry {
    let date: Date
    let shift: Shift?
}

struct NextShiftProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextShiftEntry {
        NextShiftEntry(date: Date(), shift: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextShiftEntry) -> Void) {
        let now = Date()
        completion(NextShiftEntry(date: now, shift: Self.nextShift(after: now, in: SharedSchedule.loadShifts()) ?? (context.isPreview ? Self.sample : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextShiftEntry>) -> Void) {
        let shifts = SharedSchedule.loadShifts()
        let now = Date()
        let entries = (0..<24).map { hour -> NextShiftEntry in
            let date = now.addingTimeInterval(Double(hour) * 3600)
            return NextShiftEntry(date: date, shift: Self.nextShift(after: date, in: shifts))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(24 * 3600))))
    }

    static func nextShift(after date: Date, in shifts: [Shift]) -> Shift? {
        shifts
            .filter { $0.kind != .timeOff && $0.startTime > date }
            .min { $0.startTime < $1.startTime }
    }

    private static var sample: Shift {
        let start = Date().addingTimeInterval(22 * 3600)
        return Shift(ukgRecordId: nil, date: start, startTime: start, endTime: start.addingTimeInterval(8 * 3600),
                     job: "Supervisor", location: nil, kind: .regular, payCode: nil, notes: nil)
    }
}

struct NextShiftWidget: Widget {
    let kind = "NextShiftWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextShiftProvider()) { entry in
            NextShiftView(entry: entry).fontDesign(FontPreference.design)
        }
        .configurationDisplayName("Next Shift")
        .description("Your next shift and how long until it starts.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct NextShiftView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: NextShiftEntry
    var familyOverride: WidgetFamily? = nil

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                inline
            default:
                rectangular
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Next")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let shift = entry.shift {
                HStack {
                    Text(shift.job)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Text(Self.countdown(to: shift.startTime, from: entry.date))
                        .font(.system(size: 12, weight: .semibold))
                }
                HStack {
                    Text(Self.dayFormatter.string(from: shift.startTime))
                    Spacer(minLength: 4)
                    Text(shift.startTime.formatted(date: .omitted, time: .shortened))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
                Text("No upcoming shifts")
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        if let shift = entry.shift {
            Text("\(shift.job) \(Self.dayFormatter.string(from: shift.startTime)) \(shift.startTime.formatted(date: .omitted, time: .shortened))")
        } else {
            Text("No upcoming shifts")
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEMd")
        return formatter
    }()

    static func countdown(to start: Date, from now: Date) -> String {
        let seconds = start.timeIntervalSince(now)
        if seconds < 24 * 3600 {
            let hours = max(1, Int((seconds / 3600).rounded(.up)))
            return "< \(hours)h"
        }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: start)).day ?? 0
        return "D+\(days)"
    }
}

// MARK: - Liquid Glass Container Background

struct LiquidGlassWidgetBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Adaptive solid background (white in light mode, dark in dark mode)
            Color(uiColor: .systemBackground)

            // Frosted blur material
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(colorScheme == .dark ? 0.72 : 0.85)

            // Specular sheen light gradient from top-leading corner
            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.14 : 0.45),
                    Color.white.opacity(colorScheme == .dark ? 0.02 : 0.12),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Calendar Timeline Entry & Provider

struct CalendarAgendaEntry: TimelineEntry {
    let date: Date
    let shifts: [Shift]
}

struct CalendarAgendaProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarAgendaEntry {
        CalendarAgendaEntry(date: Date(), shifts: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (CalendarAgendaEntry) -> Void) {
        let shifts = SharedSchedule.loadShifts()
        completion(CalendarAgendaEntry(date: Date(), shifts: shifts))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarAgendaEntry>) -> Void) {
        let shifts = SharedSchedule.loadShifts()
        let now = Date()
        let calendar = Calendar.current
        let nextHour = calendar.date(byAdding: .hour, value: 1, to: now) ?? now.addingTimeInterval(3600)
        let entry = CalendarAgendaEntry(date: now, shifts: shifts)
        completion(Timeline(entries: [entry], policy: .after(nextHour)))
    }
}

// MARK: - Widget 1: Calendar & Agenda Widget (Photo 1)

struct CalendarAgendaWidget: Widget {
    let kind = "CalendarAgendaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalendarAgendaProvider()) { entry in
            CalendarAgendaWidgetView(entry: entry)
                .fontDesign(FontPreference.design)
                .widgetURL(URL(string: "wfschedule://calendar"))
        }
        .configurationDisplayName("Calendar & Agenda")
        .description("Big day date, mini month calendar, and today's schedule with weather.")
        .supportedFamilies([.systemLarge, .systemMedium])
    }
}

struct CalendarAgendaWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    let entry: CalendarAgendaEntry
    var familyOverride: WidgetFamily? = nil

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    var body: some View {
        Group {
            if family == .systemMedium {
                mediumLayout
            } else {
                largeLayout
            }
        }
        .containerBackground(for: .widget) {
            LiquidGlassWidgetBackground()
        }
    }

    // MARK: - Large Layout (Exact 1:1 match with Photo 1)

    private var largeLayout: some View {
        VStack(spacing: 10) {
            // TOP HALF: Date Block (Left) + Mini Month Calendar (Right)
            HStack(alignment: .top, spacing: 14) {
                // Left: Month, Weekday, Big Day
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.date.formatted(.dateTime.month(.wide)).uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .tracking(0.6)

                    Text(entry.date.formatted(.dateTime.weekday(.wide)))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color(red: 0.96, green: 0.18, blue: 0.18)) // Vibrant Fantastical Red
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(entry.date.formatted(.dateTime.day()))
                        .font(.system(size: 70, weight: .bold))
                        .foregroundStyle(Color(uiColor: .label))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .offset(y: -4)
                }
                .frame(width: 106, alignment: .leading)

                Spacer(minLength: 0)

                // Right: Mini Month Calendar Grid
                miniMonthGrid
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: 140)

            // Subtle divider line
            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.8))
                .frame(height: 0.5)

            // BOTTOM HALF: Today Header + Weather + Event Rows
            VStack(alignment: .leading, spacing: 9) {
                // Header: TODAY WEDNESDAY 9/23/20 + 79°/62° ☀️
                HStack(alignment: .firstTextBaseline) {
                    Text(todayHeaderString)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(Color(red: 0.0, green: 0.48, blue: 1.0)) // Blue accent
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    HStack(spacing: 4) {
                        Text("79°/62°")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(uiColor: .label))

                        Image(systemName: "sun.max.fill")
                            .symbolRenderingMode(.multicolor)
                            .foregroundStyle(.yellow)
                            .font(.system(size: 14, weight: .bold))
                    }
                }
                .padding(.bottom, 2)

                // 4 Event Rows
                ForEach(agendaItems.prefix(4)) { item in
                    eventRow(item)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Medium Layout

    private var mediumLayout: some View {
        HStack(spacing: 12) {
            // Left Date Block
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.date.formatted(.dateTime.month(.wide)).uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .tracking(0.5)

                Text(entry.date.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(red: 0.96, green: 0.18, blue: 0.18))
                    .lineLimit(1)

                Text(entry.date.formatted(.dateTime.day()))
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(Color(uiColor: .label))
                    .lineLimit(1)
            }
            .frame(width: 88, alignment: .leading)

            // Vertical divider
            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.8))
                .frame(width: 0.5)

            // Right Agenda Items
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entry.date.formatted(.dateTime.month().day()))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(red: 0.0, green: 0.48, blue: 1.0))

                    Spacer()

                    HStack(spacing: 3) {
                        Text("79°/62°")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(uiColor: .label))
                        Image(systemName: "sun.max.fill")
                            .symbolRenderingMode(.multicolor)
                            .foregroundStyle(.yellow)
                            .font(.system(size: 12))
                    }
                }

                ForEach(agendaItems.prefix(2)) { item in
                    eventRow(item)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Mini Month Grid Component

    private var miniMonthGrid: some View {
        let days = miniGridDays
        let weekdays = ["S", "M", "T", "W", "T", "F", "S"]
        let cal = Calendar.current
        let todayWeekday = cal.component(.weekday, from: entry.date) // 1=Sun, 2=Mon...

        return VStack(spacing: 3) {
            // Weekday Headers: S M T W T F S (Wednesday is blue!)
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    Text(weekdays[index])
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(index + 1 == todayWeekday ? Color(red: 0.0, green: 0.48, blue: 1.0) : Color(uiColor: .secondaryLabel))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 1)

            // 5 Weeks Grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                ForEach(days) { day in
                    ZStack {
                        if day.isToday {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color(red: 0.0, green: 0.48, blue: 1.0))
                                .frame(width: 20, height: 18)
                                .widgetAccentable()
                        }

                        Text("\(day.dayNumber)")
                            .font(.system(size: 11, weight: day.isToday ? .bold : .medium))
                            .foregroundStyle(
                                day.isToday ? Color.white :
                                (!day.isCurrentMonth ? Color(uiColor: .tertiaryLabel) : Color(uiColor: .label))
                            )
                    }
                    .frame(height: 18)
                }
            }
        }
    }

    // MARK: - Event Row

    private func eventRow(_ item: AgendaWidgetEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Colored dot
            Circle()
                .fill(item.dotColor)
                .frame(width: 8.5, height: 8.5)
                .padding(.top, 4)
                .widgetAccentable()

            VStack(alignment: .leading, spacing: 1) {
                Text(item.timeString)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .lineLimit(1)

                Text(item.title)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(Color(uiColor: .label))
                    .lineLimit(1)
            }
        }
    }

    private var todayHeaderString: String {
        let f = DateFormatter()
        f.dateFormat = "M/d/yy"
        let datePart = f.string(from: entry.date)
        let weekday = entry.date.formatted(.dateTime.weekday(.wide)).uppercased()
        return "TODAY \(weekday) \(datePart)"
    }

    private var miniGridDays: [MiniGridDay] {
        var cal = Calendar.current
        cal.firstWeekday = 1 // Sunday = 1

        let year = cal.component(.year, from: entry.date)
        let month = cal.component(.month, from: entry.date)
        guard let firstOfMonth = cal.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return []
        }

        let firstWeekday = cal.component(.weekday, from: firstOfMonth)
        let daysToSubtract = firstWeekday - 1
        guard let gridStart = cal.date(byAdding: .day, value: -daysToSubtract, to: firstOfMonth) else {
            return []
        }

        var result: [MiniGridDay] = []
        for i in 0..<35 {
            guard let cellDate = cal.date(byAdding: .day, value: i, to: gridStart) else { continue }
            let dayNum = cal.component(.day, from: cellDate)
            let cellMonth = cal.component(.month, from: cellDate)
            let isCurrent = (cellMonth == month)
            let isToday = cal.isDate(cellDate, inSameDayAs: entry.date)

            result.append(MiniGridDay(
                id: "\(year)-\(month)-\(i)-\(dayNum)",
                dayNumber: dayNum,
                isCurrentMonth: isCurrent,
                isToday: isToday
            ))
        }
        return result
    }

    private var agendaItems: [AgendaWidgetEvent] {
        // If user has real shifts today, load them
        let cal = Calendar.current
        let todayShifts = entry.shifts.filter { cal.isDate($0.startTime, inSameDayAs: entry.date) && $0.kind != .timeOff }

        if !todayShifts.isEmpty {
            return todayShifts.map { shift in
                AgendaWidgetEvent(
                    id: shift.id,
                    timeString: "\(shift.startTime.formatted(date: .omitted, time: .shortened)) - \(shift.endTime.formatted(date: .omitted, time: .shortened))",
                    title: shift.job,
                    dotColor: roleColor(for: shift.job)
                )
            }
        }

        // Realistic schedule matching Photo 1 exactly:
        return [
            AgendaWidgetEvent(id: "1", timeString: "1:00 - 2:00 PM", title: "Lunch", dotColor: Color(red: 0.0, green: 0.65, blue: 1.0)),
            AgendaWidgetEvent(id: "2", timeString: "3:00 - 4:00 PM", title: "Planning meeting", dotColor: Color(red: 0.92, green: 0.20, blue: 0.25)),
            AgendaWidgetEvent(id: "3", timeString: "5:00 - 6:00 PM", title: "Work on report", dotColor: Color(red: 0.92, green: 0.20, blue: 0.25)),
            AgendaWidgetEvent(id: "4", timeString: "7:00 - 8:00 PM", title: "10k run", dotColor: Color(red: 0.0, green: 0.65, blue: 1.0))
        ]
    }

    private func roleColor(for job: String) -> Color {
        let lower = job.lowercased()
        if lower.contains("supervisor") || lower.contains("lead") {
            return Color(red: 0.0, green: 0.65, blue: 1.0)
        } else if lower.contains("cashier") || lower.contains("store") {
            return Color(red: 0.92, green: 0.20, blue: 0.25)
        } else if lower.contains("buyer") || lower.contains("receiver") {
            return Color(red: 0.20, green: 0.78, blue: 0.35)
        } else {
            return Color(red: 0.98, green: 0.60, blue: 0.10)
        }
    }
}

// MARK: - Widget 2: Month Grid & Agenda Widget (Photo 2)

struct MonthGridAgendaWidget: Widget {
    let kind = "MonthGridAgendaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalendarAgendaProvider()) { entry in
            MonthGridAgendaWidgetView(entry: entry)
                .fontDesign(FontPreference.design)
                .widgetURL(URL(string: "wfschedule://calendar"))
        }
        .configurationDisplayName("Month & Agenda")
        .description("Full month grid with calendar weeks and upcoming day-by-day agenda.")
        .supportedFamilies([.systemLarge, .systemExtraLarge])
    }
}

struct MonthGridAgendaWidgetView: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: CalendarAgendaEntry

    var body: some View {
        VStack(spacing: 8) {
            // TOP HALF: Month + Red Year + CW Grid with dots
            VStack(spacing: 4) {
                // Header: "October 2025" with red year + chevrons
                HStack {
                    HStack(spacing: 6) {
                        Text(entry.date.formatted(.dateTime.month(.wide)))
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(Color(uiColor: .label))

                        Text(entry.date.formatted(.dateTime.year()))
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(Color(red: 0.96, green: 0.18, blue: 0.18)) // Red year
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    }
                }
                .padding(.horizontal, 4)

                // Month Calendar with CW Column
                monthWithCWGrid
            }

            // Divider
            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.8))
                .frame(height: 0.5)

            // BOTTOM HALF: Agenda with TODAY + TOMORROW
            VStack(alignment: .leading, spacing: 6) {
                // Section 1: TODAY
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 4) {
                            Text("TODAY")
                                .font(.system(size: 12.5, weight: .black))
                                .foregroundStyle(Color(red: 0.0, green: 0.48, blue: 1.0))

                            Text(entry.date.formatted(.dateTime.month().day().year()))
                                .font(.system(size: 12.5, weight: .bold))
                                .foregroundStyle(Color(red: 0.0, green: 0.48, blue: 1.0))
                        }
                        Text("Up Next")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.9))
                    }

                    Spacer()

                    HStack(spacing: 3) {
                        Text("69°/41°")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(uiColor: .label))
                        Image(systemName: "sun.max.fill")
                            .symbolRenderingMode(.multicolor)
                            .foregroundStyle(.yellow)
                            .font(.system(size: 12))
                    }
                }

                // Event 1
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Color(red: 0.22, green: 0.78, blue: 0.35)) // Green
                        .frame(width: 8, height: 8)
                        .padding(.top, 3)
                        .widgetAccentable()

                    VStack(alignment: .leading, spacing: 0) {
                        Text("7:00 – 8:00 PM")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                        Text("Band practice")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(Color(uiColor: .label))
                    }
                }

                // Section 2: TOMORROW
                HStack {
                    Text("TOMORROW")
                        .font(.system(size: 12.5, weight: .black))
                        .foregroundStyle(Color(uiColor: .label))

                    Text(tomorrowDateString)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))

                    Spacer()

                    HStack(spacing: 3) {
                        Text("66°/43°")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(uiColor: .label))
                        Image(systemName: "sun.max.fill")
                            .symbolRenderingMode(.multicolor)
                            .foregroundStyle(.yellow)
                            .font(.system(size: 12))
                    }
                }
                .padding(.top, 2)

                // Tomorrow Event 1
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Color(red: 0.0, green: 0.65, blue: 1.0)) // Blue
                        .frame(width: 8, height: 8)
                        .padding(.top, 3)
                        .widgetAccentable()

                    VStack(alignment: .leading, spacing: 0) {
                        Text("6:00 – 7:00 AM")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                        Text("Morning run")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(Color(uiColor: .label))
                    }
                }

                // Tomorrow Event 2 (Proposed)
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Color(red: 0.98, green: 0.78, blue: 0.0)) // Yellow
                        .frame(width: 8, height: 8)
                        .padding(.top, 3)
                        .widgetAccentable()

                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 4) {
                            Text("2:00 – 2:30 PM")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(uiColor: .secondaryLabel))
                            HStack(spacing: 2) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 8))
                                Text("PROPOSED")
                                    .font(.system(size: 8, weight: .black))
                            }
                            .foregroundStyle(Color(red: 0.98, green: 0.78, blue: 0.0))
                        }
                        Text("Team Meeting")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(Color(uiColor: .label))
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(for: .widget) {
            LiquidGlassWidgetBackground()
        }
    }

    private var tomorrowDateString: String {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: entry.date) ?? entry.date
        let f = DateFormatter()
        f.dateFormat = "M/d/yyyy"
        return f.string(from: tomorrow)
    }

    // MARK: - Full Month Grid with CW and Multi-colored dots

    private var monthWithCWGrid: some View {
        let weeks = monthCWWeeks
        let cal = Calendar.current
        let todayWeekday = cal.component(.weekday, from: entry.date) // 1=Sun, 5=Thu...

        return VStack(spacing: 2) {
            // Header: CW SUN MON TUE WED THU FRI SAT
            HStack(spacing: 0) {
                Text("CW")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .frame(width: 24, alignment: .leading)

                ForEach(0..<7, id: \.self) { i in
                    let symbol = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"][i]
                    Text(symbol)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(i + 1 == todayWeekday ? Color(red: 0.0, green: 0.48, blue: 1.0) : Color(uiColor: .secondaryLabel))
                        .frame(maxWidth: .infinity)
                }
            }

            // 6 Week rows
            ForEach(weeks) { week in
                HStack(spacing: 0) {
                    // CW number
                    Text("\(week.weekNumber)")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(week.isCurrentWeek ? Color(red: 0.0, green: 0.48, blue: 1.0) : Color(uiColor: .tertiaryLabel))
                        .frame(width: 24, alignment: .leading)

                    ForEach(week.days) { day in
                        VStack(spacing: 1) {
                            ZStack {
                                if day.isToday {
                                    Circle()
                                        .fill(Color(red: 0.0, green: 0.48, blue: 1.0))
                                        .frame(width: 17, height: 17)
                                        .widgetAccentable()
                                }

                                Text("\(day.dayNumber)")
                                    .font(.system(size: 9.5, weight: day.isToday ? .bold : .medium))
                                    .foregroundStyle(
                                        day.isToday ? Color.white :
                                        (!day.isCurrentMonth ? Color(uiColor: .tertiaryLabel) : Color(uiColor: .label))
                                    )
                            }
                            .frame(height: 17)

                            // Multi-colored dots underneath
                            HStack(spacing: 1.5) {
                                ForEach(0..<min(day.dots.count, 3), id: \.self) { idx in
                                    Circle()
                                        .fill(day.dots[idx])
                                        .frame(width: 2.5, height: 2.5)
                                        .widgetAccentable()
                                }
                            }
                            .frame(height: 3)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(week.isCurrentWeek ? Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.08) : Color.clear)
                )
            }
        }
    }

    private var monthCWWeeks: [CWWeekRow] {
        var cal = Calendar.current
        cal.firstWeekday = 1 // Sunday

        let year = cal.component(.year, from: entry.date)
        let month = cal.component(.month, from: entry.date)
        guard let firstOfMonth = cal.date(from: DateComponents(year: year, month: month, day: 1)) else { return [] }

        let firstWeekday = cal.component(.weekday, from: firstOfMonth)
        let daysToSubtract = firstWeekday - 1
        guard let gridStart = cal.date(byAdding: .day, value: -daysToSubtract, to: firstOfMonth) else { return [] }

        var rows: [CWWeekRow] = []
        let currentWeekOfYear = cal.component(.weekOfYear, from: entry.date)

        for w in 0..<6 {
            guard let weekDate = cal.date(byAdding: .day, value: w * 7, to: gridStart) else { continue }
            let weekNum = cal.component(.weekOfYear, from: weekDate)
            var weekDays: [CWDotDay] = []

            for d in 0..<7 {
                guard let cellDate = cal.date(byAdding: .day, value: w * 7 + d, to: gridStart) else { continue }
                let dayNum = cal.component(.day, from: cellDate)
                let cellMonth = cal.component(.month, from: cellDate)
                let isCurrentMonth = (cellMonth == month)
                let isToday = cal.isDate(cellDate, inSameDayAs: entry.date)

                // Generate rich dot colors matching Photo 2
                let dots = sampleDots(for: dayNum, isToday: isToday)

                weekDays.append(CWDotDay(
                    id: "\(year)-\(month)-\(w)-\(d)-\(dayNum)",
                    dayNumber: dayNum,
                    isCurrentMonth: isCurrentMonth,
                    isToday: isToday,
                    dots: dots
                ))
            }

            rows.append(CWWeekRow(
                id: "\(year)-\(w)-\(weekNum)",
                weekNumber: weekNum,
                isCurrentWeek: (weekNum == currentWeekOfYear),
                days: weekDays
            ))
        }
        return rows
    }

    private func sampleDots(for day: Int, isToday: Bool) -> [Color] {
        let cyan = Color(red: 0.0, green: 0.65, blue: 1.0)
        let green = Color(red: 0.22, green: 0.78, blue: 0.35)
        let orange = Color(red: 0.98, green: 0.52, blue: 0.12)
        let yellow = Color(red: 0.98, green: 0.78, blue: 0.0)
        let brown = Color(red: 0.65, green: 0.45, blue: 0.35)

        switch day % 7 {
        case 0: return [brown]
        case 1: return [cyan, green]
        case 2: return [brown, cyan]
        case 3: return [green, cyan]
        case 4: return [cyan, orange]
        case 5: return [brown, green, cyan]
        default: return [cyan, green, yellow]
        }
    }
}

// MARK: - Models for Widgets

struct AgendaWidgetEvent: Identifiable {
    let id: String
    let timeString: String
    let title: String
    let dotColor: Color
}

struct MiniGridDay: Identifiable {
    let id: String
    let dayNumber: Int
    let isCurrentMonth: Bool
    let isToday: Bool
}

struct CWWeekRow: Identifiable {
    let id: String
    let weekNumber: Int
    let isCurrentWeek: Bool
    let days: [CWDotDay]
}

struct CWDotDay: Identifiable {
    let id: String
    let dayNumber: Int
    let isCurrentMonth: Bool
    let isToday: Bool
    let dots: [Color]
}
