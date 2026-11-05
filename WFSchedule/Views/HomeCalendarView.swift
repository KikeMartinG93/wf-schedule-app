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

/// Represents an event or shift in the agenda
private struct RichAgendaItem: Identifiable {
    enum Kind {
        case task(task: ChecklistTask)
        case shift(shift: Shift)
    }

    let id: String
    let kind: Kind
}

/// Month-grid and Day-ticker calendar and agenda view styled identically to Fantastical's iconic iOS layout:
/// - Top card with large "Month Year" header (red year), weekday columns or day ticker strip.
/// - Vertical drag on the header expands the compact ticker into a full month grid, and drags it back.
/// - Agenda feed below with weather ranges, "TODAY / Up Next", colored event dots, interactive task checkboxes,
///   and continuous vertical scrolling across next and previous days.
/// Classic, Light, and Dark display styles (picked independently for Light Mode
/// and Dark Mode in Settings) swap the header and agenda chrome.
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
    @AppStorage("payPreferencesConfigured") private var payPreferencesConfigured = false
    @AppStorage("payPaymentMethod") private var payPaymentMethod = ""
    @AppStorage("payPaydayWeekday") private var payPaydayWeekday = ""
    @AppStorage(PayPreferences.showPayPeriodMarkersKey) private var showPayPeriodMarkers = false
    /// 0 = compact day ticker, 1 = full month grid. Driven by a vertical drag
    /// on the white calendar header, matching Fantastical's expand/collapse.
    @State private var expansion: CGFloat = 0
    @State private var isDraggingCalendar = false
    @State private var dragStartExpansion: CGFloat = 0

    @State private var index = ShiftIndex(ScheduleStore.shared.load()?.shifts ?? [])
    private var shifts: [Shift] { index.all }

    @State private var displayedMonth: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    /// Shared dial position: the horizontal ticker and vertical agenda both
    /// report and follow these, so scrolling one turns the other.
    @State private var tickerDay: Date? = Calendar.current.startOfDay(for: Date())
    @State private var agendaDay: Date? = Calendar.current.startOfDay(for: Date())

    @State private var completedTaskIDs: Set<UUID> = []

    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var weatherStore = WorkWeatherStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    private var calendar: Calendar { Calendar.current }

    private var displayStyle: CalendarDisplayStyle { theme.displayStyle(for: colorScheme) }
    private var chrome: CalendarDisplayPalette { displayStyle.palette }

    var body: some View {
        NavigationStack {
            ZStack {
                chrome.agendaBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    calendarCard

                    agendaView
                }
                .blur(radius: needsSignIn ? 14 : 0)
                .allowsHitTesting(!needsSignIn)
                .accessibilityHidden(needsSignIn)

                if needsSignIn {
                    chrome.agendaBackground.opacity(0.35)
                        .overlay(Color.red.opacity(displayStyle.agendaIsDark ? 0.25 : 0.12))
                        .ignoresSafeArea()
                        .allowsHitTesting(false)

                    signInOverlay
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .animation(.easeInOut(duration: 0.22), value: displayStyle)
            .onAppear {
                expansion = calendarDayTickerMode ? 0 : 1
                reloadShifts()
                reloadTasks()
                handleJump()
                weatherStore.refreshIfNeeded()
            }
            .onChange(of: calendarDayTickerMode) { _, isTicker in
                guard !isDraggingCalendar else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.84)) {
                    expansion = isTicker ? 0 : 1
                }
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
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    weatherStore.refreshIfNeeded()
                }
            }
            .onChange(of: selectedDate) { _, newDate in
                let start = calendar.startOfDay(for: newDate)
                if tickerDay.map({ !calendar.isDate($0, inSameDayAs: start) }) ?? true {
                    tickerDay = start
                }
                if agendaDay.map({ !calendar.isDate($0, inSameDayAs: start) }) ?? true {
                    agendaDay = start
                }
                if !calendar.isDate(start, equalTo: displayedMonth, toGranularity: .month) {
                    displayedMonth = start
                }
            }
            .onChange(of: tickerDay) { _, newDay in
                commitDialDay(newDay)
            }
            .onChange(of: agendaDay) { _, newDay in
                commitDialDay(newDay)
            }
        }
    }

    // MARK: - Expandable Calendar Card

    private static let tickerBodyHeight: CGFloat = 96
    private static let gridBodyHeight: CGFloat = 308

    private var calendarBodyHeight: CGFloat {
        Self.tickerBodyHeight + (Self.gridBodyHeight - Self.tickerBodyHeight) * expansion
    }

    /// White header that morphs from the compact day ticker into the full month
    /// grid as you drag it vertically — the same hide/show as Fantastical.
    private var calendarCard: some View {
        VStack(spacing: 0) {
            monthHeader
                .padding(.horizontal, 20)
                .padding(.top, 6)

            ZStack(alignment: .top) {
                monthGridBody
                    .opacity(expansion)
                    .allowsHitTesting(expansion > 0.5)

                dayTickerStrip
                    .padding(.top, 4)
                    .padding(.bottom, 0)
                    .opacity(1 - expansion)
                    .allowsHitTesting(expansion < 0.5)
            }
            .frame(height: calendarBodyHeight, alignment: .top)
            .clipped()

            VStack(spacing: 0) {
                shiftLegend
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 2)
                    .padding(.bottom, 2)

                dragHandle
            }
        }
        .background(chrome.calendarBackground)
        .overlay(alignment: .bottom) {
            if !displayStyle.agendaIsDark {
                Rectangle()
                    .fill(chrome.divider)
                    .frame(height: 0.5)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(verticalExpandGesture)
    }

    /// Job colors on the first row; holiday / payday / pay-period on the second.
    private var shiftLegend: some View {
        VStack(alignment: .leading, spacing: 4) {
            FlowLayout(spacing: 12, rowSpacing: 4) {
                ForEach(legendJobs, id: \.self) { job in
                    HStack(spacing: 5) {
                        Capsule()
                            .fill(colorForJob(job))
                            .frame(width: 12, height: 3.5)
                        Text(verbatim: job)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(chrome.calendarSecondary)
                            .lineLimit(1)
                    }
                }
            }

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    SparklyStar(size: 8)
                    Text("Holiday pay")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(chrome.calendarSecondary)
                        .lineLimit(1)
                }

                if PayPreferences.showsPayday {
                    HStack(spacing: 4) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(red: 0.20, green: 0.72, blue: 0.40))
                        Text("Payday")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(chrome.calendarSecondary)
                            .lineLimit(1)
                    }
                }

                if PayPreferences.showsPayday && showPayPeriodMarkers {
                    HStack(spacing: 4) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(PayPeriodMarkerStyle.start)
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(PayPeriodMarkerStyle.end)
                        Text("Pay period")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(chrome.calendarSecondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .id("\(payPreferencesConfigured)-\(payPaymentMethod)-\(payPaydayWeekday)-\(showPayPeriodMarkers)")
    }

    private var legendJobs: [String] {
        var seen = Set<String>()
        var jobs: [String] = []
        for shift in index.sortedByStart {
            if seen.insert(shift.job).inserted { jobs.append(shift.job) }
        }
        return jobs.isEmpty ? ["Supervisor", "Cash Office"] : jobs
    }

    private var dragHandle: some View {
        Capsule()
            .fill(chrome.handle)
            .frame(width: 38, height: 4.5)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .contentShape(Rectangle())
            .onTapGesture {
                setCalendarExpanded(expansion < 0.5)
            }
            .accessibilityLabel(expansion < 0.5 ? "Show month" : "Hide month")
    }

    private var verticalExpandGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if !isDraggingCalendar {
                    guard abs(dy) > abs(dx) else { return }
                    isDraggingCalendar = true
                    dragStartExpansion = expansion
                }
                let range = max(Self.gridBodyHeight - Self.tickerBodyHeight, 1)
                expansion = min(1, max(0, dragStartExpansion + dy / range))
            }
            .onEnded { value in
                guard isDraggingCalendar else { return }
                isDraggingCalendar = false
                let flick = value.predictedEndTranslation.height - value.translation.height
                let expand: Bool
                if abs(flick) > 80 {
                    expand = flick > 0
                } else {
                    expand = expansion >= 0.45
                }
                setCalendarExpanded(expand)
            }
    }

    private func setCalendarExpanded(_ expanded: Bool) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.84)) {
            expansion = expanded ? 1 : 0
            calendarDayTickerMode = !expanded
        }
    }

    private var dayTickerStrip: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(dialDays, id: \.self) { day in
                        dayTickerColumn(for: day)
                            .id(day)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    selectDialDay(day)
                                }
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $tickerDay, anchor: .center)
            .contentMargins(.horizontal, max(0, (geo.size.width - 66) / 2), for: .scrollContent)
        }
        .frame(height: Self.tickerBodyHeight)
    }

    /// Stable day span shared by the ticker and agenda so they can scroll
    /// independently without the window jumping back around the selection.
    private var dialDays: [Date] {
        let today = calendar.startOfDay(for: Date())
        return (-120...240).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }

    private func selectDialDay(_ day: Date) {
        let start = calendar.startOfDay(for: day)
        selectedDate = start
        displayedMonth = start
        tickerDay = start
        agendaDay = start
    }

    private func commitDialDay(_ day: Date?) {
        guard let day else { return }
        let start = calendar.startOfDay(for: day)
        guard !calendar.isDate(start, inSameDayAs: selectedDate) else { return }
        selectedDate = start
    }

    private func dayTickerColumn(for day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)
        let dayNumber = calendar.component(.day, from: day)
        let weekdaySymbol = day.formatted(.dateTime.weekday(.abbreviated)).uppercased()
        let hasTasks = hasChecklistTasks(on: day)
        let shiftColors = tickerShiftBarColors(for: day)
        let payday = isPayday(day)
        let periodStart = isPayPeriodStart(day)
        let periodEnd = isPayPeriodEnd(day)

        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                // Top row: optional checkbox / payday icons + uppercase weekday
                HStack(spacing: 3) {
                    if hasTasks {
                        Image(systemName: "checkmark.square.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(red: 0.95, green: 0.25, blue: 0.25))
                    }
                    if payday {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(red: 0.20, green: 0.72, blue: 0.40))
                    }

                    Text(weekdaySymbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isToday ? chrome.today : chrome.calendarMuted)
                }
                .frame(height: 18)
                .padding(.top, 4)

                // Day number
                Text("\(dayNumber)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(chrome.calendarPrimary)
                    .padding(.top, 2)

                // Selected-day bar uses the Settings theme accent. Shift bars
                // under it use the same job colors as the legend.
                VStack(spacing: 2) {
                    if isSelected {
                        Capsule()
                            .fill(theme.current.readableAccent)
                            .frame(width: 48, height: 4)
                    }
                    ForEach(Array(shiftColors.enumerated()), id: \.offset) { _, color in
                        Capsule()
                            .fill(color)
                            .frame(width: 48, height: 4)
                    }
                    HStack(spacing: 3) {
                        if isHolidayPay(day) {
                            SparklyStar(size: 8)
                        }
                        if payday {
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color(red: 0.20, green: 0.72, blue: 0.40))
                        }
                        if periodStart {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(PayPeriodMarkerStyle.start)
                        }
                        if periodEnd {
                            Image(systemName: "flag.checkered")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(PayPeriodMarkerStyle.end)
                        }
                    }
                    .frame(height: 10)
                }
                .frame(height: 28, alignment: .top)
                .padding(.top, 2)
            }
            .frame(width: 66, height: Self.tickerBodyHeight, alignment: .top)
            .background(isSelected ? chrome.selectedColumn : chrome.calendarBackground)

            // Hairline vertical divider
            Rectangle()
                .fill(chrome.divider)
                .frame(width: 0.5)
        }
    }

    /// Job colors for up to two shifts on a ticker day, matching the legend.
    private func tickerShiftBarColors(for day: Date) -> [Color] {
        var seen = Set<String>()
        var colors: [Color] = []
        for shift in index.shifts(on: day, calendar: calendar) {
            guard seen.insert(shift.job).inserted else { continue }
            colors.append(colorForJob(shift.job))
            if colors.count == 2 { break }
        }
        return colors
    }

    // MARK: - Month Grid

    private var monthGridBody: some View {
        VStack(spacing: 0) {
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
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            if value.translation.width < -40 {
                                changeMonth(by: 1)
                            } else if value.translation.width > 40 {
                                changeMonth(by: -1)
                            }
                        }
                )
        }
    }

    /// Shown whenever the selected day isn't today, or the header is on another month.
    private var isViewingToday: Bool {
        calendar.isDateInToday(selectedDate)
            && calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
    }

    private var monthHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(displayedMonth.formatted(.dateTime.month(.wide)).capitalized)
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(chrome.calendarPrimary)

            Text(displayedMonth.formatted(.dateTime.year()))
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(chrome.year)

            Spacer()

            if !isViewingToday {
                Button {
                    jumpToToday()
                } label: {
                    Text("Today")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(chrome.today)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(chrome.today.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isViewingToday)
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
                    .foregroundStyle(isTodayColumn ? chrome.today : chrome.calendarMuted)
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
                            isHolidayPay: isHolidayPay(day),
                            isPayday: isPayday(day),
                            isPayPeriodStart: isPayPeriodStart(day),
                            isPayPeriodEnd: isPayPeriodEnd(day),
                            chrome: chrome
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectDialDay(day)
                            }
                        }
                    }
                }
                .background {
                    if week.contains(where: { calendar.isDate($0, inSameDayAs: selectedDate) }) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(chrome.selectedWeek)
                    }
                }
            }
        }
    }

    // MARK: - Agenda View with Continuous Vertical Scrolling

    private var agendaView: some View {
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
                            .foregroundStyle(chrome.agendaTertiary)
                            .padding(.top, 40)
                        Text("No shifts scheduled for this period")
                            .font(.subheadline)
                            .foregroundStyle(chrome.agendaSecondary)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(agendaDays, id: \.self) { day in
                        agendaSection(for: day)
                            .id(day)
                    }
                }

                // Room to scroll the last rows clear of the floating shift bar.
                Color.clear.frame(height: 64)
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollPosition(id: $agendaDay, anchor: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .background(chrome.agendaBackground)
    }

    /// Continuous range of past and upcoming days for smooth vertical scrolling
    private var visibleAgendaDays: [Date] {
        if calendarDayTickerMode {
            return dialDays
        } else {
            var daysSet = Set<Date>()
            daysSet.insert(calendar.startOfDay(for: selectedDate))
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
        let weather = weatherStore.weather(on: day)
        let items = itemsForAgendaDay(day)

        return Section {
            VStack(spacing: 0) {
                if isPayday(day) {
                    paydayBanner(for: day)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 6)
                }
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

    private func agendaHeader(day: Date, isToday: Bool, isTomorrow: Bool, weather: DayWeather?) -> some View {
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
                    .foregroundStyle(chrome.today)

                    Text("Up Next")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(chrome.today)
                } else if isTomorrow {
                    HStack(spacing: 6) {
                        Text("TOMORROW")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(chrome.agendaPrimary)
                        Text(shortDate)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(chrome.agendaSecondary)
                    }
                } else {
                    let weekdayName = day.formatted(.dateTime.weekday(.wide)).uppercased()
                    HStack(spacing: 6) {
                        Text(weekdayName)
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(chrome.agendaPrimary)
                        Text(shortDate)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(chrome.agendaSecondary)
                    }
                }
            }

            Spacer()

            if let weather {
                HStack(spacing: 5) {
                    Text("\(weather.highTemp)°/\(weather.lowTemp)°")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(chrome.agendaWeather)

                    if weather.symbolName.contains("sun") {
                        Image(systemName: weather.symbolName)
                            .font(.system(size: 15))
                            .symbolRenderingMode(.multicolor)
                    } else {
                        Image(systemName: weather.symbolName)
                            .font(.system(size: 15))
                            .foregroundStyle(chrome.agendaPrimary)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 6)
        .background(chrome.stickyHeader)
    }

    private func paydayBanner(for day: Date) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "dollarsign.circle.fill")
                .foregroundStyle(Color(red: 0.20, green: 0.72, blue: 0.40))
            VStack(alignment: .leading, spacing: 1) {
                Text("Payday")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(chrome.agendaPrimary)
                if let period = PaydayCalendar.periodDescription(forPayday: day) {
                    Text("Pay period \(period)")
                        .font(.system(size: 12))
                        .foregroundStyle(chrome.agendaSecondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(red: 0.20, green: 0.72, blue: 0.40).opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Rich Agenda Items

    private func itemsForAgendaDay(_ day: Date) -> [RichAgendaItem] {
        var items: [RichAgendaItem] = []

        let dayShifts = index.shifts(on: day, calendar: calendar)
        for shift in dayShifts {
            items.append(RichAgendaItem(id: "shift-\(shift.id)", kind: .shift(shift: shift)))
        }

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
        case .task(let task):
            agendaTaskRow(task: task)

        case .shift(let shift):
            agendaShiftRow(shift: shift)
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
                    .foregroundStyle(chrome.agendaSecondary)

                Text(shift.job)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(chrome.agendaPrimary)

                if let location = shift.location {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 10))
                        Text(location)
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(chrome.agendaTertiary)
                }

                if let notes = shift.notes {
                    Text(notes)
                        .font(.system(size: 12))
                        .foregroundStyle(chrome.agendaTertiary)
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

    private func isPayday(_ day: Date) -> Bool {
        PaydayCalendar.isPayday(day, calendar: calendar)
    }

    private func isPayPeriodStart(_ day: Date) -> Bool {
        PaydayCalendar.isPayPeriodStart(day, calendar: calendar)
    }

    private func isPayPeriodEnd(_ day: Date) -> Bool {
        PaydayCalendar.isPayPeriodEnd(day, calendar: calendar)
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
                        .foregroundStyle(chrome.agendaSecondary)

                    Text(task.title)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(isDone ? chrome.agendaTertiary : chrome.agendaPrimary)
                        .strikethrough(isDone, color: chrome.agendaTertiary)
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
                .strokeBorder(chrome.emptyStroke, lineWidth: 1.5)
                .frame(width: 10, height: 10)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text("No shift scheduled")
                    .font(.system(size: 15))
                    .foregroundStyle(chrome.agendaTertiary)

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

    private func colorForJob(_ job: String) -> Color {
        Shift.accentColor(forJob: job, theme: theme.current)
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
        var seen = Set<String>()
        var colors: [Color] = []
        for shift in index.shifts(on: day, calendar: calendar) {
            guard seen.insert(shift.job).inserted else { continue }
            colors.append(colorForJob(shift.job))
        }
        return Array(colors.prefix(4))
    }

    private func hasChecklistTasks(on day: Date) -> Bool {
        calendar.isDateInToday(day) && !checklistTasksForToday.isEmpty
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
        withAnimation(.easeInOut(duration: 0.25)) {
            selectDialDay(calendar.startOfDay(for: Date()))
        }
    }

    private func handleJump() {
        guard let jump, jump.id != handledJumpID else { return }
        handledJumpID = jump.id
        withAnimation(.easeInOut(duration: 0.25)) {
            selectDialDay(calendar.startOfDay(for: jump.date))
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
                .foregroundStyle(chrome.demoBannerText)
            Spacer()
            Button("Exit") { DemoMode.set(false) }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(chrome.today)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(chrome.demoBannerFill, in: Capsule())
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
    let isPayday: Bool
    let isPayPeriodStart: Bool
    let isPayPeriodEnd: Bool
    let chrome: CalendarDisplayPalette

    private var calendar: Calendar { Calendar.current }
    private var dayNumber: Int { calendar.component(.day, from: day) }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if isToday {
                    Circle()
                        .fill(chrome.today)
                        .frame(width: 32, height: 32)
                } else if isSelected {
                    Circle()
                        .strokeBorder(chrome.today, lineWidth: 2)
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
                if isPayday {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(isToday ? Color.white : Color(red: 0.20, green: 0.72, blue: 0.40))
                }
                if isPayPeriodStart {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 5.5, weight: .bold))
                        .foregroundStyle(isToday ? Color.white : PayPeriodMarkerStyle.start)
                }
                if isPayPeriodEnd {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 5.5, weight: .bold))
                        .foregroundStyle(isToday ? Color.white : PayPeriodMarkerStyle.end)
                }
                ForEach(Array(dots.enumerated()), id: \.offset) { _, col in
                    Circle()
                        .fill(isToday ? Color.white : col)
                        .frame(width: 4.5, height: 4.5)
                }
                if hasTasks {
                    Image(systemName: "checkmark")
                        .font(.system(size: 6, weight: .black))
                        .foregroundStyle(isToday ? Color.white : chrome.today)
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
            return chrome.calendarPrimary
        } else {
            return chrome.outOfMonth
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

/// Wraps legend chips onto the next line instead of clipping them.
private struct FlowLayout: Layout {
    var spacing: CGFloat
    var rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + rowSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            usedWidth = max(usedWidth, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: usedWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + rowSpacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
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
