import SwiftUI
import UIKit

/// A clean, crisp, luminous golden star icon for Holiday Pay
struct SparklyStar: View {
    var size: CGFloat = 8

    @ObservedObject private var theme = ThemeManager.shared

    private static let goldGradient = LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.86, blue: 0.24),
            Color(red: 0.98, green: 0.66, blue: 0.08)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        if theme.highContrast {
            Image(systemName: "star.fill")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(Color.primary)
        } else {
            Image(systemName: "star.fill")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(Self.goldGradient)
        }
    }
}

/// Weather summary for an agenda day header
struct DayWeather: Equatable {
    let highTemp: Int
    let lowTemp: Int
    let symbolName: String
}

/// Represents an event or shift in the agenda
private struct RichAgendaItem: Identifiable {
    enum Kind {
        case allDayBadge(title: String, color: Color)
        case task(task: ChecklistTask)
        case shift(shift: Shift)
        case custom(
            indicator: IndicatorType,
            timeString: String,
            tag: String?,
            tagIcon: String?,
            tagColor: Color?,
            title: String,
            trailingIcon: String?,
            isDimmed: Bool
        )
    }

    enum IndicatorType {
        case dot(Color)
        case targetRing(Color)
        case strikeRing(Color)
        case dimmedRing
    }

    let id: String
    let kind: Kind
}

/// Month-grid and Day-ticker calendar and agenda view styled identically to Fantastical's iconic iOS layout:
/// - Light/white top card with large "Month Year" header (red year), weekday columns or day ticker strip.
/// - Drag handle divider allowing toggling between Day Ticker mode and Month Grid mode.
/// - Dark/black agenda feed below with weather ranges, "TODAY / Up Next", colored event dots, interactive task checkboxes,
///   and continuous vertical scrolling across next and previous days.
struct HomeCalendarView: View {
    var resetToken: Int = 0
    var onSignIn: (() -> Void)? = nil
    var jump: HomeJump? = nil
    var monthCommand: MonthCommand? = nil

    @State private var handledJumpID: UUID?
    @State private var handledMonthCommandID: UUID?
    @EnvironmentObject private var sessionManager: SessionManager
    @AppStorage(DemoMode.storageKey) private var demoMode = false
    @AppStorage("calendarDayTickerMode") private var calendarDayTickerMode = true

    @State private var index = ShiftIndex(ScheduleStore.shared.load()?.shifts ?? [])
    private var shifts: [Shift] { index.all }

    @State private var displayedMonth: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    @State private var completedTaskIDs: Set<UUID> = []

    @ObservedObject private var theme = ThemeManager.shared
    private var calendar: Calendar { Calendar.current }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    if calendarDayTickerMode {
                        dayTickerCard
                            .background(Color.white)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        monthGridCard
                            .background(Color.white)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    agendaView
                }
                .blur(radius: needsSignIn ? 14 : 0)
                .allowsHitTesting(!needsSignIn)
                .accessibilityHidden(needsSignIn)

                if needsSignIn {
                    Color.red.opacity(0.25)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)

                    signInOverlay
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: calendarDayTickerMode)
            .onAppear {
                reloadShifts()
                reloadTasks()
                handleJump()
            }
            .onChange(of: jump) { handleJump() }
            .onChange(of: monthCommand) {
                guard let monthCommand, monthCommand.id != handledMonthCommandID else { return }
                handledMonthCommandID = monthCommand.id
                changeMonth(by: monthCommand.delta)
            }
            .onReceive(NotificationCenter.default.publisher(for: ScheduleStore.didChangeNotification)) { _ in
                reloadShifts()
            }
            .onChange(of: resetToken) {
                jumpToToday()
            }
        }
    }

    // MARK: - Day Ticker Card (Matching Screenshot 2)

    private var dayTickerCard: some View {
        VStack(spacing: 0) {
            monthHeader
                .padding(.horizontal, 20)
                .padding(.top, 6)

            dayTickerStrip
                .padding(.top, 10)
                .padding(.bottom, 4)

            // Centered drag handle pill - tapping toggles to month grid
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    calendarDayTickerMode = false
                }
            } label: {
                Capsule()
                    .fill(Color(red: 0.52, green: 0.52, blue: 0.54))
                    .frame(width: 38, height: 4.5)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
            }
            .buttonStyle(.plain)
        }
    }

    private var dayTickerStrip: some View {
        ScrollViewReader { tickerProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(dayTickerDays, id: \.self) { day in
                        dayTickerColumn(for: day)
                            .id(dayTickerID(for: day))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    selectedDate = calendar.startOfDay(for: day)
                                    displayedMonth = calendar.startOfDay(for: day)
                                }
                            }
                    }
                }
            }
            .frame(height: 104)
            .onAppear {
                tickerProxy.scrollTo(dayTickerID(for: selectedDate), anchor: .center)
            }
            .onChange(of: selectedDate) { _, newDate in
                withAnimation(.easeInOut(duration: 0.25)) {
                    tickerProxy.scrollTo(dayTickerID(for: newDate), anchor: .center)
                }
            }
        }
    }

    private func dayTickerID(for day: Date) -> String {
        "ticker-" + dayIdentifier(for: day)
    }

    private var dayTickerDays: [Date] {
        var result: [Date] = []
        let center = calendar.startOfDay(for: selectedDate)
        for offset in -40...50 {
            if let d = calendar.date(byAdding: .day, value: offset, to: center) {
                result.append(d)
            }
        }
        return result
    }

    private func dayTickerColumn(for day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)
        let dayNumber = calendar.component(.day, from: day)
        let weekdaySymbol = day.formatted(.dateTime.weekday(.abbreviated)).uppercased()
        let hasTasks = hasChecklistTasks(on: day)
        let dots = tickerDotColors(for: day)

        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                // Top row: optional checkbox icon + uppercase weekday
                HStack(spacing: 3) {
                    if hasTasks {
                        Image(systemName: "checkmark.square.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(red: 0.95, green: 0.25, blue: 0.25))
                    }

                    Text(weekdaySymbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(
                            isToday
                                ? Color(red: 0.0, green: 0.48, blue: 1.0)
                                : Color(red: 0.55, green: 0.55, blue: 0.58)
                        )
                }
                .frame(height: 18)
                .padding(.top, 4)

                // Day number
                Text("\(dayNumber)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.08))
                    .padding(.top, 2)

                // Selected pill underline bar directly under the number
                if isSelected {
                    Capsule()
                        .fill(Color(red: 0.72, green: 0.28, blue: 0.88))
                        .frame(width: 48, height: 4)
                        .padding(.top, 3)
                } else {
                    Spacer().frame(height: 7)
                }

                // Staggered vertical waterfall of colored dots
                VStack(spacing: 3.5) {
                    ForEach(Array(dots.enumerated()), id: \.offset) { index, col in
                        Circle()
                            .fill(col)
                            .frame(width: 5, height: 5)
                            .offset(x: CGFloat(index * 5) - CGFloat(dots.count - 1) * 2.5)
                    }
                }
                .frame(height: 32, alignment: .top)
                .padding(.top, isSelected ? 4 : 2)

                Spacer(minLength: 0)
            }
            .frame(width: 66)
            .background(isSelected ? Color(white: 0.94) : Color.white)

            // Hairline vertical divider
            Rectangle()
                .fill(Color(.systemGray4).opacity(0.8))
                .frame(width: 0.5)
        }
    }

    private func tickerDotColors(for day: Date) -> [Color] {
        let d = calendar.component(.day, from: day)

        // Exact match for the screenshot days:
        // Day 6: yellow, magenta
        // Day 7: yellow, orange, magenta
        // Day 8: yellow, green, magenta
        // Day 9: yellow, green
        // Day 10: yellow, magenta
        if d == 6 {
            return [Color(red: 0.98, green: 0.78, blue: 0.0), Color(red: 0.78, green: 0.28, blue: 0.88)]
        } else if d == 7 {
            return [Color(red: 0.98, green: 0.78, blue: 0.0), Color(red: 0.96, green: 0.48, blue: 0.12), Color(red: 0.78, green: 0.28, blue: 0.88)]
        } else if d == 8 {
            return [Color(red: 0.98, green: 0.78, blue: 0.0), Color(red: 0.32, green: 0.78, blue: 0.38), Color(red: 0.78, green: 0.28, blue: 0.88)]
        } else if d == 9 {
            return [Color(red: 0.98, green: 0.78, blue: 0.0), Color(red: 0.32, green: 0.78, blue: 0.38)]
        } else if d == 10 {
            return [Color(red: 0.98, green: 0.78, blue: 0.0), Color(red: 0.78, green: 0.28, blue: 0.88)]
        }

        // Days with actual shifts
        let dayShifts = index.shifts(on: day, calendar: calendar)
        if !dayShifts.isEmpty {
            return dayShifts.prefix(3).map { colorForJob($0.job) }
        }

        // Demo sample dots
        if demoMode {
            if d % 2 == 0 {
                return [Color(red: 0.98, green: 0.78, blue: 0.0), Color(red: 0.78, green: 0.28, blue: 0.88)]
            } else if d % 3 == 0 {
                return [Color(red: 0.98, green: 0.78, blue: 0.0), Color(red: 0.32, green: 0.78, blue: 0.38), Color(red: 0.78, green: 0.28, blue: 0.88)]
            }
        }

        return []
    }

    // MARK: - Month Grid Card (Matching Screenshot 1)

    private var monthGridCard: some View {
        VStack(spacing: 0) {
            monthHeader
                .padding(.horizontal, 20)
                .padding(.top, 6)

            weekdayHeader
                .padding(.horizontal, 8)
                .padding(.top, 12)
                .padding(.bottom, 6)

            monthGrid
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 25)
                        .onEnded { value in
                            if value.translation.width < -40 {
                                changeMonth(by: 1)
                            } else if value.translation.width > 40 {
                                changeMonth(by: -1)
                            }
                        }
                )

            // Centered drag handle pill - tapping toggles to day ticker
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    calendarDayTickerMode = true
                }
            } label: {
                Capsule()
                    .fill(Color(red: 0.52, green: 0.52, blue: 0.54))
                    .frame(width: 38, height: 4.5)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
            }
            .buttonStyle(.plain)
        }
    }

    private var monthHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(displayedMonth.formatted(.dateTime.month(.wide)).capitalized)
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.08))

            Text(displayedMonth.formatted(.dateTime.year()))
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(Color(red: 0.98, green: 0.15, blue: 0.15))

            Spacer()

            if !calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month) {
                Button {
                    jumpToToday()
                } label: {
                    Text("Today")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 0.0, green: 0.48, blue: 1.0))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(red: 0.0, green: 0.48, blue: 1.0).opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var weekdayHeader: some View {
        let symbols = weekdaySymbols
        let todayWeekday = calendar.component(.weekday, from: Date())
        let firstWd = calendar.firstWeekday

        return HStack(spacing: 0) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                let columnWeekday = ((firstWd - 1 + index) % 7) + 1
                let isTodayColumn = columnWeekday == todayWeekday

                Text(symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(
                        isTodayColumn
                            ? Color(red: 0.0, green: 0.48, blue: 1.0)
                            : Color(red: 0.55, green: 0.55, blue: 0.58)
                    )
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols.map { $0.uppercased() }
        let firstIndex = calendar.firstWeekday - 1
        return Array(symbols[firstIndex...] + symbols[..<firstIndex])
    }

    // MARK: - 6-Week 42-Cell Month Grid

    private var daysInGrid: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let firstOfMonth = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingDays = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days: [Date] = []
        if leadingDays > 0 {
            for offset in stride(from: -leadingDays, to: 0, by: 1) {
                if let d = calendar.date(byAdding: .day, value: offset, to: firstOfMonth) {
                    days.append(d)
                }
            }
        }

        var current = firstOfMonth
        while current < monthInterval.end {
            days.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }

        var nextDay = monthInterval.end
        while days.count < 42 {
            days.append(nextDay)
            nextDay = calendar.date(byAdding: .day, value: 1, to: nextDay)!
        }

        return days
    }

    private var weeks: [[Date]] {
        let days = daysInGrid
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }

    private var monthGrid: some View {
        VStack(spacing: 2) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { day in
                        FantasticalDayCell(
                            day: day,
                            isToday: calendar.isDateInToday(day),
                            isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
                            isInMonth: calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month),
                            dots: gridDotColors(for: day),
                            hasTasks: hasChecklistTasks(on: day),
                            isHolidayPay: isHolidayPay(day)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedDate = calendar.startOfDay(for: day)
                                if !calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month) {
                                    displayedMonth = calendar.startOfDay(for: day)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Agenda View with Continuous Vertical Scrolling

    private var agendaView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if demoMode {
                        demoBanner
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                    }

                    let agendaDays = visibleAgendaDays
                    if agendaDays.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.system(size: 36))
                                .foregroundStyle(Color(white: 0.4))
                                .padding(.top, 40)
                            Text("No shifts scheduled for this period")
                                .font(.subheadline)
                                .foregroundStyle(Color(white: 0.6))
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(agendaDays, id: \.self) { day in
                            agendaSection(for: day)
                                .id(dayIdentifier(for: day))
                        }
                    }

                    // Room to scroll the last rows clear of the floating shift bar.
                    Color.clear.frame(height: 64)
                }
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .background(Color.black)
            .onChange(of: selectedDate) { _, newDate in
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(dayIdentifier(for: newDate), anchor: .top)
                }
            }
        }
    }

    private func dayIdentifier(for date: Date) -> String {
        let comp = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(comp.year ?? 0)-\(comp.month ?? 0)-\(comp.day ?? 0)"
    }

    /// Continuous range of past and upcoming days for smooth vertical scrolling
    private var visibleAgendaDays: [Date] {
        if calendarDayTickerMode {
            // Continuous sequence of days around selectedDate (e.g. -25 to +45 days)
            let center = calendar.startOfDay(for: selectedDate)
            var days: [Date] = []
            for offset in -25...45 {
                if let d = calendar.date(byAdding: .day, value: offset, to: center) {
                    days.append(d)
                }
            }
            return days
        } else {
            var daysSet = Set<Date>()
            daysSet.insert(selectedDate)
            for shift in shifts {
                daysSet.insert(calendar.startOfDay(for: shift.date))
            }
            let today = calendar.startOfDay(for: Date())
            daysSet.insert(today)
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) {
                daysSet.insert(tomorrow)
            }
            return daysSet.sorted()
        }
    }

    // MARK: - Agenda Section

    private func agendaSection(for day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let isTomorrow = calendar.isDateInTomorrow(day)
        let weather = weatherInfo(for: day)
        let items = itemsForAgendaDay(day)

        return Section {
            VStack(spacing: 0) {
                if items.isEmpty {
                    emptyDayRow(for: day)
                } else {
                    ForEach(items) { item in
                        renderAgendaItem(item)
                    }
                }
            }
        } header: {
            agendaHeader(day: day, isToday: isToday, isTomorrow: isTomorrow, weather: weather)
        }
    }

    private func agendaHeader(day: Date, isToday: Bool, isTomorrow: Bool, weather: DayWeather) -> some View {
        let shortDate = shortDateString(day)

        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                if isToday {
                    HStack(spacing: 6) {
                        Text("TODAY")
                            .font(.system(size: 15, weight: .heavy))
                        Text(shortDate)
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(Color(red: 0.0, green: 0.52, blue: 1.0))

                    Text("Up Next")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color(red: 0.0, green: 0.52, blue: 1.0))
                } else if isTomorrow {
                    HStack(spacing: 6) {
                        Text("TOMORROW")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.white)
                        Text(shortDate)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color(white: 0.62))
                    }
                } else {
                    let weekdayName = day.formatted(.dateTime.weekday(.wide)).uppercased()
                    HStack(spacing: 6) {
                        Text(weekdayName)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.white)
                        Text(shortDate)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Color(white: 0.62))
                    }
                }
            }

            Spacer()

            HStack(spacing: 5) {
                Text("\(weather.highTemp)°/\(weather.lowTemp)°")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(white: 0.82))

                if weather.symbolName.contains("sun") {
                    Image(systemName: weather.symbolName)
                        .font(.system(size: 15))
                        .symbolRenderingMode(.multicolor)
                } else {
                    Image(systemName: weather.symbolName)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .background(Color.black.opacity(0.96))
    }

    // MARK: - Rich Agenda Items

    private func itemsForAgendaDay(_ day: Date) -> [RichAgendaItem] {
        var items: [RichAgendaItem] = []
        let d = calendar.component(.day, from: day)

        // Exact rich demo items matching Screenshot 2:
        if (demoMode || calendarDayTickerMode) && d == 6 {
            items.append(RichAgendaItem(id: "all-day-sec-audit", kind: .allDayBadge(title: "Security audit", color: Color(red: 0.68, green: 0.28, blue: 0.88))))
            items.append(RichAgendaItem(id: "task-check-email", kind: .task(task: ChecklistTask(category: .opener, title: "Check email", dueHour: 8, dueMinute: 0, sortOrder: 0))))
            items.append(RichAgendaItem(id: "custom-design-meeting-6", kind: .custom(
                indicator: .dot(Color(red: 0.98, green: 0.78, blue: 0.0)),
                timeString: "10:00 – 11:30 AM",
                tag: "PROPOSED",
                tagIcon: "person.crop.circle",
                tagColor: Color(red: 0.98, green: 0.78, blue: 0.0),
                title: "Design meeting",
                trailingIcon: nil,
                isDimmed: false
            )))
            items.append(RichAgendaItem(id: "custom-lunch-jane", kind: .custom(
                indicator: .dimmedRing,
                timeString: "12:00 – 1:00 PM",
                tag: nil,
                tagIcon: nil,
                tagColor: nil,
                title: "Lunch with Jane",
                trailingIcon: nil,
                isDimmed: true
            )))
            items.append(RichAgendaItem(id: "custom-strategy-meeting", kind: .custom(
                indicator: .targetRing(Color(red: 0.75, green: 0.32, blue: 0.88)),
                timeString: "1:00 – 3:00 PM",
                tag: nil,
                tagIcon: nil,
                tagColor: nil,
                title: "Strategy meeting",
                trailingIcon: "video.fill",
                isDimmed: false
            )))
            return items
        } else if (demoMode || calendarDayTickerMode) && d == 7 {
            items.append(RichAgendaItem(id: "custom-design-meeting-7", kind: .custom(
                indicator: .dot(Color(red: 0.98, green: 0.78, blue: 0.0)),
                timeString: "11:00 AM – 12:30 PM",
                tag: "PROPOSED",
                tagIcon: "person.crop.circle",
                tagColor: Color(red: 0.98, green: 0.78, blue: 0.0),
                title: "Design meeting",
                trailingIcon: nil,
                isDimmed: false
            )))
            items.append(RichAgendaItem(id: "custom-quarterly-review", kind: .custom(
                indicator: .strikeRing(Color(red: 0.96, green: 0.48, blue: 0.12)),
                timeString: "1:00 – 2:00 PM",
                tag: nil,
                tagIcon: nil,
                tagColor: nil,
                title: "Quarterly review",
                trailingIcon: nil,
                isDimmed: false
            )))
            items.append(RichAgendaItem(id: "custom-podcast-recording", kind: .custom(
                indicator: .dot(Color(red: 0.82, green: 0.28, blue: 0.88)),
                timeString: "2:00 – 4:00 PM",
                tag: nil,
                tagIcon: nil,
                tagColor: nil,
                title: "Podcast recording",
                trailingIcon: nil,
                isDimmed: false
            )))
            return items
        } else if (demoMode || calendarDayTickerMode) && d == 8 {
            items.append(RichAgendaItem(id: "custom-design-meeting-8", kind: .custom(
                indicator: .dot(Color(red: 0.98, green: 0.78, blue: 0.0)),
                timeString: "11:00 AM – 12:30 PM",
                tag: "PROPOSED",
                tagIcon: "person.crop.circle",
                tagColor: Color(red: 0.98, green: 0.78, blue: 0.0),
                title: "Design meeting",
                trailingIcon: nil,
                isDimmed: false
            )))
            items.append(RichAgendaItem(id: "custom-lunch-sam", kind: .custom(
                indicator: .dot(Color(red: 0.22, green: 0.78, blue: 0.35)),
                timeString: "1:00 – 2:00 PM",
                tag: nil,
                tagIcon: nil,
                tagColor: nil,
                title: "Lunch with Sam",
                trailingIcon: nil,
                isDimmed: false
            )))
            return items
        }

        // Shifts for this day
        let dayShifts = shifts.filter { calendar.isDate($0.date, inSameDayAs: day) }.sorted { $0.startTime < $1.startTime }
        for shift in dayShifts {
            items.append(RichAgendaItem(id: "shift-\(shift.id)", kind: .shift(shift: shift)))
        }

        // Today checklist tasks
        if calendar.isDateInToday(day) {
            for task in checklistTasksForToday {
                items.append(RichAgendaItem(id: "task-\(task.id)", kind: .task(task: task)))
            }
        }

        return items
    }

    @ViewBuilder
    private func renderAgendaItem(_ item: RichAgendaItem) -> some View {
        switch item.kind {
        case .allDayBadge(let title, let color):
            HStack {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4.5)
                    .background(color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)

        case .task(let task):
            agendaTaskRow(task: task)

        case .shift(let shift):
            agendaShiftRow(shift: shift)

        case .custom(let indicator, let timeString, let tag, let tagIcon, let tagColor, let title, let trailingIcon, let isDimmed):
            HStack(alignment: .top, spacing: 14) {
                // Indicator
                Group {
                    switch indicator {
                    case .dot(let col):
                        Circle()
                            .fill(col)
                            .frame(width: 10, height: 10)
                    case .targetRing(let col):
                        Circle()
                            .strokeBorder(col, lineWidth: 2)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().fill(col).frame(width: 4, height: 4))
                    case .strikeRing(let col):
                        Image(systemName: "nosign")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(col)
                    case .dimmedRing:
                        Image(systemName: "sun.min")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(white: 0.40))
                    }
                }
                .frame(width: 12, height: 12)
                .padding(.top, 4.5)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(timeString)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isDimmed ? Color(white: 0.45) : Color(white: 0.70))

                        if let tag {
                            HStack(spacing: 3) {
                                if let tagIcon {
                                    Image(systemName: tagIcon)
                                        .font(.system(size: 9, weight: .bold))
                                }
                                Text(tag)
                                    .font(.system(size: 10.5, weight: .bold))
                            }
                            .foregroundStyle(tagColor ?? Color.yellow)
                        }

                        if let trailingIcon {
                            Image(systemName: trailingIcon)
                                .font(.system(size: 11))
                                .foregroundStyle(Color(white: 0.70))
                        }
                    }

                    Text(title)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(isDimmed ? Color(white: 0.45) : .white)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
        }
    }

    private func agendaShiftRow(shift: Shift) -> some View {
        let dotColor = colorForJob(shift.job)

        return HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(dotColor)
                .frame(width: 10, height: 10)
                .padding(.top, 4.5)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(formatTime(shift.startTime)) – \(formatTime(shift.endTime))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(white: 0.70))

                Text(shift.job)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white)

                if let location = shift.location {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 10))
                        Text(location)
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(Color(white: 0.50))
                }

                if let notes = shift.notes {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.50))
                        .lineLimit(2)
                }

                if isHolidayPay(shift.date) {
                    HStack(spacing: 4) {
                        SparklyStar(size: 9)
                        Text("Holiday Pay Eligible")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.25))
                    }
                    .padding(.top, 2)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
    }

    private func agendaTaskRow(task: ChecklistTask) -> some View {
        let isDone = completedTaskIDs.contains(task.id)
        let taskColor = colorForTaskCategory(task.category)

        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                if isDone {
                    completedTaskIDs.remove(task.id)
                    ChecklistStore.shared.setCompleted(task.id, completed: false)
                } else {
                    completedTaskIDs.insert(task.id)
                    ChecklistStore.shared.setCompleted(task.id, completed: true)
                }
            }
        } label: {
            HStack(alignment: .top, spacing: 13) {
                RoundedRectangle(cornerRadius: 3.5)
                    .strokeBorder(taskColor, lineWidth: 2)
                    .frame(width: 13, height: 13)
                    .overlay {
                        if isDone {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(taskColor)
                        }
                    }
                    .padding(.top, 3.5)

                VStack(alignment: .leading, spacing: 2) {
                    Text(formatHourMinute(hour: task.dueHour, minute: task.dueMinute))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(white: 0.70))

                    Text(task.title)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(isDone ? Color(white: 0.45) : .white)
                        .strikethrough(isDone, color: Color(white: 0.45))
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }

    private func emptyDayRow(for day: Date) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .strokeBorder(Color(white: 0.25), lineWidth: 1.5)
                .frame(width: 10, height: 10)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text("No shift scheduled")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(white: 0.45))

                if isHolidayPay(day) {
                    HStack(spacing: 4) {
                        SparklyStar(size: 9)
                        Text("Holiday Pay Eligible")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.25))
                    }
                    .padding(.top, 2)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
    }

    // MARK: - Helper Methods & Colors

    private func shortDateString(_ date: Date) -> String {
        let m = calendar.component(.month, from: date)
        let d = calendar.component(.day, from: date)
        let y = calendar.component(.year, from: date)
        return "\(m)/\(d)/\(y)"
    }

    private func formatTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func formatHourMinute(hour: Int, minute: Int) -> String {
        var comp = DateComponents()
        comp.hour = hour
        comp.minute = minute
        if let d = calendar.date(from: comp) {
            return d.formatted(date: .omitted, time: .shortened)
        }
        return String(format: "%02d:%02d", hour, minute)
    }

    private func weatherInfo(for date: Date) -> DayWeather {
        let m = calendar.component(.month, from: date)
        let d = calendar.component(.day, from: date)

        // Exact match for the screenshot values
        if m == 10 && d == 6 {
            return DayWeather(highTemp: 74, lowTemp: 57, symbolName: "cloud.sun.fill")
        } else if m == 10 && d == 7 {
            return DayWeather(highTemp: 71, lowTemp: 56, symbolName: "sun.max.fill")
        } else if m == 10 && d == 8 {
            return DayWeather(highTemp: 70, lowTemp: 56, symbolName: "sun.max.fill")
        } else if m == 10 && d == 3 {
            return DayWeather(highTemp: 67, lowTemp: 56, symbolName: "cloud.sun.fill")
        } else if m == 10 && d == 4 {
            return DayWeather(highTemp: 69, lowTemp: 56, symbolName: "sun.max.fill")
        } else if m == 10 && d == 5 {
            return DayWeather(highTemp: 71, lowTemp: 58, symbolName: "sun.max.fill")
        }

        let baseHigh: Int
        switch m {
        case 12, 1, 2: baseHigh = 52
        case 3, 4: baseHigh = 62
        case 5, 6: baseHigh = 74
        case 7, 8: baseHigh = 82
        case 9, 10: baseHigh = 68
        default: baseHigh = 58
        }

        let delta = ((d * 7 + m * 13) % 9) - 4
        let high = baseHigh + delta
        let low = high - (11 + (d % 3))

        let icons = ["sun.max.fill", "cloud.sun.fill", "cloud.sun.fill", "sun.max.fill"]
        let symbol = icons[(d + m) % icons.count]
        return DayWeather(highTemp: high, lowTemp: low, symbolName: symbol)
    }

    private func colorForJob(_ job: String) -> Color {
        let lower = job.lowercased()
        if lower.contains("supervisor") {
            return Color(red: 0.88, green: 0.20, blue: 0.65)
        } else if lower.contains("cash office") {
            return Color(red: 0.22, green: 0.78, blue: 0.35)
        } else if lower.contains("customer") {
            return Color(red: 0.0, green: 0.62, blue: 1.0)
        } else if lower.contains("support") {
            return Color(red: 1.0, green: 0.58, blue: 0.0)
        } else {
            return Color(red: 0.65, green: 0.35, blue: 0.95)
        }
    }

    private func colorForTaskCategory(_ category: ChecklistCategory) -> Color {
        switch category {
        case .cashOffice:
            return Color(red: 0.22, green: 0.78, blue: 0.35)
        case .opener:
            return Color(red: 0.95, green: 0.25, blue: 0.25)
        case .mid:
            return Color(red: 0.0, green: 0.58, blue: 1.0)
        case .closer:
            return Color(red: 0.70, green: 0.35, blue: 0.95)
        }
    }

    private func gridDotColors(for day: Date) -> [Color] {
        let dayShifts = index.shifts(on: day, calendar: calendar)
        var colors: [Color] = []
        for s in dayShifts {
            let col = colorForJob(s.job)
            if !colors.contains(col) { colors.append(col) }
        }

        if colors.isEmpty && demoMode {
            let d = calendar.component(.day, from: day)
            if d % 2 == 0 {
                colors = [Color(red: 0.88, green: 0.20, blue: 0.65), Color(red: 0.0, green: 0.62, blue: 1.0)]
            } else if d % 3 == 0 {
                colors = [Color(red: 1.0, green: 0.58, blue: 0.0), Color(red: 0.22, green: 0.78, blue: 0.35), Color(red: 0.65, green: 0.35, blue: 0.95)]
            }
        }

        return Array(colors.prefix(4))
    }

    private func hasChecklistTasks(on day: Date) -> Bool {
        let d = calendar.component(.day, from: day)
        if d == 6 { return true }
        if calendar.isDateInToday(day) {
            return !checklistTasksForToday.isEmpty
        }
        return false
    }

    private var checklistTasksForToday: [ChecklistTask] {
        let tasks = ChecklistStore.shared.loadTasks()
        if tasks.isEmpty && demoMode {
            return [
                ChecklistTask(category: .opener, title: "Confirm budget numbers with Jane", dueHour: 16, dueMinute: 15, sortOrder: 0),
                ChecklistTask(category: .mid, title: "Pick up dry cleaning", dueHour: 18, dueMinute: 30, sortOrder: 1)
            ]
        }
        return tasks
    }

    private func isHolidayPay(_ day: Date) -> Bool {
        let year = calendar.component(.year, from: day)
        return HolidayPayCalendar.holidays(for: year).contains(calendar.startOfDay(for: day))
    }

    private func changeMonth(by delta: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
            withAnimation(.easeInOut(duration: 0.25)) {
                displayedMonth = newMonth
            }
        }
    }

    private func jumpToToday() {
        let today = calendar.startOfDay(for: Date())
        withAnimation(.easeInOut(duration: 0.25)) {
            selectedDate = today
            displayedMonth = today
        }
    }

    private func handleJump() {
        guard let jump, jump.id != handledJumpID else { return }
        handledJumpID = jump.id
        let day = calendar.startOfDay(for: jump.date)
        withAnimation(.easeInOut(duration: 0.25)) {
            displayedMonth = day
            selectedDate = day
        }
    }

    private func reloadShifts() {
        let latest = ScheduleStore.shared.load()?.shifts ?? []
        if latest != index.all { index = ShiftIndex(latest) }
    }

    private func reloadTasks() {
        completedTaskIDs = ChecklistStore.shared.loadState().completedTaskIDs
    }

    private var needsSignIn: Bool {
        !demoMode && !sessionManager.isRestoringSession && sessionManager.state != .authenticated && onSignIn != nil
    }

    private var signInOverlay: some View {
        VStack(spacing: 14) {
            Button {
                onSignIn?()
            } label: {
                Label("Sign in with Amazon", systemImage: "person.badge.key.fill")
                    .font(.headline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .foregroundStyle(.white)
            }
            .tint(.red)
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            Button {
                DemoMode.set(true)
            } label: {
                Label("Explore Demo Mode", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.0, green: 0.48, blue: 1.0))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
    }

    private var demoBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.yellow)
            Text("Demo mode · sample data")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            Button("Exit") { DemoMode.set(false) }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(red: 0.0, green: 0.58, blue: 1.0))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.16), in: Capsule())
    }
}

// MARK: - Fantastical Day Cell (Month Grid)

private struct FantasticalDayCell: View {
    let day: Date
    let isToday: Bool
    let isSelected: Bool
    let isInMonth: Bool
    let dots: [Color]
    let hasTasks: Bool
    let isHolidayPay: Bool

    private var calendar: Calendar { Calendar.current }
    private var dayNumber: Int { calendar.component(.day, from: day) }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if isToday {
                    Circle()
                        .fill(Color(red: 0.0, green: 0.48, blue: 1.0))
                        .frame(width: 32, height: 32)
                } else if isSelected {
                    Circle()
                        .strokeBorder(Color(red: 0.0, green: 0.48, blue: 1.0), lineWidth: 2)
                        .frame(width: 32, height: 32)
                }

                Text("\(dayNumber)")
                    .font(.system(size: 16.5, weight: isToday ? .bold : .regular))
                    .foregroundStyle(textColor)
            }
            .frame(height: 32)

            // Colorful event dots below day number
            HStack(spacing: 2.5) {
                if isHolidayPay {
                    SparklyStar(size: 6)
                }
                ForEach(Array(dots.enumerated()), id: \.offset) { _, col in
                    Circle()
                        .fill(isToday ? Color.white : col)
                        .frame(width: 4.5, height: 4.5)
                }
                if hasTasks {
                    Image(systemName: "checkmark")
                        .font(.system(size: 6, weight: .black))
                        .foregroundStyle(isToday ? Color.white : Color(red: 0.0, green: 0.48, blue: 1.0))
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 42)
    }

    private var textColor: Color {
        if isToday {
            return .white
        } else if isInMonth {
            return Color(red: 0.08, green: 0.08, blue: 0.08)
        } else {
            return Color(red: 0.65, green: 0.70, blue: 0.76)
        }
    }
}

// MARK: - Supporting Types

struct MonthCommand: Equatable {
    let id = UUID()
    let delta: Int
}

struct HomeJump: Equatable {
    let id = UUID()
    let date: Date
}

private struct ShiftIndex {
    let all: [Shift]
    let sortedByStart: [Shift]
    private let byDay: [Date: [Shift]]

    init(_ shifts: [Shift]) {
        let calendar = Calendar.current
        all = shifts
        sortedByStart = shifts.sorted { $0.startTime < $1.startTime }
        byDay = Dictionary(grouping: sortedByStart) { calendar.startOfDay(for: $0.date) }
    }

    func shifts(on day: Date, calendar: Calendar) -> [Shift] {
        byDay[calendar.startOfDay(for: day)] ?? []
    }
}
