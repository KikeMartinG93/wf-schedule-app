import SwiftUI
import UIKit

/// Month-grid calendar (styled after Apple Calendar's month view) with a
/// selected-day event list below. Reads from the same locally-persisted
/// schedule `ScheduleListView` syncs — this view doesn't trigger its own
/// network sync, just re-reads the store when it appears, so switching tabs
/// never causes a duplicate/racing fetch.
struct HomeCalendarView: View {
    /// Bumped by MainTabView when the Home tab is tapped while already
    /// active — the standard "tap the active tab to jump home" gesture.
    var resetToken: Int = 0
    /// Opens the chosen sign-in sheet; offered in front of the blurred calendar
    /// whenever there's no signed-in session.
    var onSignIn: ((SessionBackend) -> Void)? = nil
    /// Which sign-in the overlay is currently set to — Innerview to start with.
    /// Its color tints the whole overlay, so the screen always says which one a
    /// tap on the big button will open.
    @State private var selectedLogin: SessionBackend = .innerview
    /// Asks Home to show a particular day (the countdown pill's "take me to my
    /// next shift"). Each request has its own id so asking for the same day twice works.
    var jump: HomeJump? = nil
    /// Month steps from the arrows on the bottom bar (see `ShiftCountdownAccessory`),
    /// each with its own id so stepping the same way twice works.
    var monthCommand: MonthCommand? = nil
    @State private var handledJumpID: UUID?
    @State private var handledMonthCommandID: UUID?
    @EnvironmentObject private var sessionManager: SessionManager
    @AppStorage(DemoMode.storageKey) private var demoMode = false

    /// The schedule, pre-grouped by day so each calendar cell is a dictionary
    /// lookup instead of a scan (and sort) of every shift on every redraw.
    @State private var index = ShiftIndex(ScheduleStore.shared.load()?.shifts ?? [])
    private var shifts: [Shift] { index.all }
    @State private var displayedMonth: Date = Calendar.current.startOfDay(for: Date())
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    /// Shared horizontal position for BOTH the current day's content and,
    /// while a swipe/navigation is in flight, the target day's content —
    /// they move together in one continuous motion (one sliding out exactly
    /// as the other slides in), which is what actually reads as a "push"
    /// instead of two separate animations chained back to back.
    @State private var pageOffset: CGFloat = 0
    /// The day being swiped/navigated TO, non-nil only while that motion is
    /// in flight. `selectedDate` itself only updates once the push finishes.
    @State private var pendingTargetDate: Date?
    /// +1 while pushing toward the future (target enters from the right),
    /// -1 toward the past (target enters from the left).
    @State private var pendingDirection: Int = 1
    /// Measured width of the day-list area, used so the target day's content
    /// starts exactly one screen-width off (no gap, no overlap) — captured
    /// from the actual view via `GeometryReader` since hardcoding a width
    /// wouldn't match every device.
    @State private var pageWidth: CGFloat = 390
    @ObservedObject private var theme = ThemeManager.shared

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                calendarContent
                    // Signed out: the calendar behind is real UI, just not
                    // usable yet, so it's blurred rather than swapped out —
                    // reads immediately as "there's a schedule here, you just
                    // need to sign in" instead of an empty/broken screen.
                    .blur(radius: needsSignIn ? 14 : 0)
                    .allowsHitTesting(!needsSignIn)
                    .accessibilityHidden(needsSignIn)

                if needsSignIn {
                    // A signed-out state reads as a warning, not just "empty" —
                    // the tint on the blur says that before any text does, and
                    // takes the color of whichever sign-in is selected.
                    ZStack {
                        // Orange laid straight over the app's green background
                        // goes khaki, so for that one the green is washed out
                        // first and the tint mixes with a clean surface instead.
                        if selectedLogin == .innerview {
                            Color(.systemBackground).opacity(0.6)
                        }
                        loginColor(selectedLogin).opacity(selectedLogin == .innerview ? 0.3 : 0.25)
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                    signInOverlay
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                reloadShifts()
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

    private var calendarContent: some View {
        VStack(spacing: 0) {
            monthHeader
            weekdayHeader
            monthGrid
                .padding(.top, 8)

            legend
                .padding(.horizontal)
                .padding(.top, 12)

            Divider()
                .padding(.top, 14)

            if demoMode {
                demoBanner
            }

            if !needsSignIn || !shifts.isEmpty {
                dayEventList
                    .contentShape(Rectangle())
                    .gesture(swipeGesture)
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    private func handleJump() {
        guard let jump, jump.id != handledJumpID else { return }
        handledJumpID = jump.id
        let day = calendar.startOfDay(for: jump.date)
        displayedMonth = day
        navigate(to: day)
    }

    private func reloadShifts() {
        let latest = ScheduleStore.shared.load()?.shifts ?? []
        if latest != index.all { index = ShiftIndex(latest) }
    }

    /// Waits for `attemptCookieRestore` to actually resolve before showing
    /// the sign-in prompt — otherwise this was true (and the red overlay
    /// visible) on every single launch for the second or so it takes to
    /// confirm the saved session is still good, even when it is.
    private var needsSignIn: Bool {
        !demoMode && !sessionManager.isRestoringSession && sessionManager.state != .authenticated && onSignIn != nil
    }

    private func loginColor(_ login: SessionBackend) -> Color {
        // A golden orange rather than system yellow, which turns to mustard mud
        // once it's tinting the whole screen at 25%.
        login == .innerview ? Color(red: 1.0, green: 0.62, blue: 0.04) : .red
    }

    /// The only things shown in front of the blurred calendar — deliberately just
    /// the two sign-ins, no explanatory text. The selected one is the filled
    /// button and a tap on it signs in; a tap on the other one only selects it,
    /// which recolors the overlay to match. Demo mode is still reachable from
    /// Settings.
    private var signInOverlay: some View {
        VStack(spacing: 14) {
            loginButton(.innerview, title: "Innerview Login")
            loginButton(.ukg, title: "Amazon Login")
        }
    }

    @ViewBuilder
    private func loginButton(_ login: SessionBackend, title: LocalizedStringKey) -> some View {
        let isSelected = selectedLogin == login
        let color = loginColor(login)
        let button = Button {
            if isSelected {
                onSignIn?(login)
            } else {
                withAnimation(.easeInOut(duration: 0.25)) { selectedLogin = login }
            }
        } label: {
            Label(title, systemImage: "person.badge.key.fill")
                .font(.headline)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                // White on yellow doesn't read, so that one button gets dark text.
                .foregroundStyle(isSelected && login == .innerview ? Color.black : (isSelected ? Color.white : color))
        }
        .tint(color)
        .controlSize(.large)
        .accessibilityHint(isSelected ? "Opens sign in" : "Selects this sign-in")
        if isSelected {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
    }

    private var demoBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(theme.current.readableAccent)
            Text("Demo mode · sample data")
                .font(.footnote.weight(.semibold))
            Spacer()
            Button("Exit") { DemoMode.set(false) }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
        .padding(.horizontal)
        .padding(.top, 10)
    }

    private func jumpToToday() {
        let today = calendar.startOfDay(for: Date())
        navigate(to: today)
        if !calendar.isDate(today, equalTo: displayedMonth, toGranularity: .month) {
            displayedMonth = today
        }
    }

    // MARK: - Header

    /// Two lines, big-title-then-small-caption — matching List's "My
    /// Schedule" (big) + "Last synced …" (small) pattern. This is flipped
    /// from the original year-above/month-below stack: the month is now the
    /// big top line, so `.firstTextBaseline` (which aligns to each child's
    /// FIRST line) lines this title's baseline up with the arrow buttons
    /// using the big text, not the small one.
    private var monthHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayedMonth.formatted(.dateTime.month(.wide)))
                    .font(.largeTitle.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(displayedMonth.formatted(.dateTime.year()))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            // `id: \.self` breaks here: `veryShortWeekdaySymbols` for en_US is
            // ["S","M","T","W","T","F","S"] — "T" (Tue/Thu) and "S" (Sun/Sat)
            // collide, and SwiftUI explicitly warns duplicate IDs give
            // "undefined results". Confirmed live via that exact warning in the
            // device log. Index-based IDs are always unique regardless of what
            // the locale's symbols look like.
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        // No horizontal inset: the week rows below run edge to edge, and the
        // letters have to sit over the same seven equal columns.
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let firstIndex = calendar.firstWeekday - 1
        return Array(symbols[firstIndex...] + symbols[..<firstIndex])
    }

    // MARK: - Grid

    /// Height of one week row. Rows are split by full-width hairlines and the
    /// day number sits at the top of its cell, like Apple Calendar's month view.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The month grid grows with Dynamic Type only up to a point — seven columns
    /// have to keep fitting the screen width, so (like Apple Calendar) the day
    /// numbers stop growing past xxxLarge while everything else keeps scaling.
    private var gridScale: CGFloat {
        switch dynamicTypeSize {
        case ...DynamicTypeSize.large: 1
        case .xLarge: 1.04
        case .xxLarge: 1.08
        default: 1.12
        }
    }

    private var weekRowHeight: CGFloat { 66 * gridScale }

    private var weeks: [[Date?]] {
        var days = daysInGrid
        while days.count % 7 != 0 { days.append(nil) }
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<$0 + 7]) }
    }

    private var monthGrid: some View {
        VStack(spacing: 0) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                Divider()
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            DayCell(
                                day: day,
                                isToday: calendar.isDateInToday(day),
                                isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
                                isHolidayPay: isHolidayPay(day),
                                isWeekend: calendar.isDateInWeekend(day),
                                accentColors: shiftColors(on: day),
                                jobs: jobs(on: day),
                                scale: gridScale
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                navigate(to: day)
                            }
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: weekRowHeight)
            }
        }
    }

    private var daysInGrid: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingEmpty = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingEmpty)
        var current = monthInterval.start
        while current < monthInterval.end {
            days.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        return days
    }

    /// Key for what each circle/dot color on the grid means, as two rows: day
    /// markers (Today / Selected / Holiday pay) on top, then the kinds of work.
    /// Job entries come from the shifts actually pulled for this account in the
    /// displayed month (so a Supervisor sees Supervisor, someone on Produce sees
    /// Production TM / Floral TM, and nobody sees jobs they never work). "Holiday
    /// pay" only appears when a holiday-pay day is in the displayed month.
    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                // High contrast draws today as a ring, so its key has to be one too.
                legendItem(color: Color(.label), text: Text("Today"), ring: theme.highContrast)
                legendItem(color: theme.current.accent, label: "Selected")
                if hasHolidayPayInDisplayedMonth {
                    HStack(spacing: 5) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.readable(theme.current.holidayPay, minimumContrast: 3))
                        Text("Holiday pay")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            if !jobsInDisplayedMonth.isEmpty {
                FlowLayout(spacing: 16, rowSpacing: 6) {
                    ForEach(jobsInDisplayedMonth, id: \.self) { job in
                        legendItem(color: Shift.accentColor(forJob: job, theme: theme.current), job: job)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var jobsInDisplayedMonth: [String] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        var seen = Set<String>()
        var jobs: [String] = []
        for shift in index.sortedByStart where interval.contains(shift.date) {
            if seen.insert(shift.job).inserted { jobs.append(shift.job) }
        }
        return jobs
    }

    private var hasHolidayPayInDisplayedMonth: Bool {
        daysInGrid.contains { day in day.map(isHolidayPay) ?? false }
    }

    private func legendItem(color: Color, label: LocalizedStringKey) -> some View {
        legendItem(color: color, text: Text(label))
    }

    /// Job names come straight from UKG, so they're shown as-is, never translated.
    private func legendItem(color: Color, job: String) -> some View {
        legendItem(color: color, text: Text(verbatim: job))
    }

    private func legendItem(color: Color, text: Text, ring: Bool = false) -> some View {
        HStack(spacing: 5) {
            if ring {
                Circle().strokeBorder(color, lineWidth: 1.5).frame(width: 8, height: 8)
            } else {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            text
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// Distinct job names that day, in shift order (used for VoiceOver).
    private func jobs(on day: Date) -> [String] {
        var seen = Set<String>()
        return index.shifts(on: day, calendar: calendar)
            .compactMap { seen.insert($0.job).inserted ? $0.job : nil }
    }

    /// One color per distinct kind of work that day (at most three), in shift order.
    private func shiftColors(on day: Date) -> [Color] {
        var seenJobs = Set<String>()
        var colors: [Color] = []
        for shift in index.shifts(on: day, calendar: calendar) {
            if seenJobs.insert(shift.job).inserted {
                colors.append(shift.accentColor(theme: theme.current))
            }
        }
        return Array(colors.prefix(3))
    }

    private func isHolidayPay(_ day: Date) -> Bool {
        let year = calendar.component(.year, from: day)
        return HolidayPayCalendar.holidays(for: year).contains(calendar.startOfDay(for: day))
    }

    private func changeMonth(by delta: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = newMonth
        }
    }

    // MARK: - Day event list

    /// The scrollable shift list for one arbitrary day (not necessarily
    /// `selectedDate`) — `dayEventList` renders this twice during a push: once
    /// for the outgoing day, once for the incoming one.
    private func dayContent(for date: Date) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                let dayShifts = index.shifts(on: date, calendar: calendar)

                if dayShifts.isEmpty {
                    Text("No shift on \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 24)
                } else {
                    ForEach(Array(dayShifts.enumerated()), id: \.element.id) { index, shift in
                        DayEventRow(shift: shift)
                        if index < dayShifts.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .padding()
            .padding(.bottom, 60)
        }
    }

    /// Renders the current day's content plus, while `pendingTargetDate` is
    /// set, the target day's content positioned exactly one `pageWidth` to
    /// whichever side it's entering from. Both share `pageOffset`, so as one
    /// slides out the other slides in over the exact same motion — a real
    /// push, not two separate animations handed off to each other.
    private var dayEventList: some View {
        GeometryReader { geo in
            ZStack {
                dayContent(for: selectedDate)
                    .offset(x: pageOffset)

                if let pendingTargetDate {
                    dayContent(for: pendingTargetDate)
                        .offset(x: pageOffset + (pendingDirection > 0 ? geo.size.width : -geo.size.width))
                }
            }
            .onAppear { pageWidth = geo.size.width }
            .onChange(of: geo.size.width) { _, newValue in pageWidth = newValue }
        }
        // Without this, whichever side is sliding out can briefly poke
        // outside the list's own area (over the tab bar, etc.) mid-animation.
        .clipped()
    }

    // MARK: - Swipe between adjacent calendar days

    /// Fast, slightly bouncy settle — matches the snappy, low-travel-time
    /// feel of a native paging transition (Photos, Calendar's own day view)
    /// rather than a fixed slower ease. Reused for a committed push, a
    /// cancelled swipe's snap-back, and every non-gesture navigation (tap,
    /// jump-to-today) so they all feel consistent.
    private var daySwipeAnimation: Animation {
        .spring(response: 0.28, dampingFraction: 0.86)
    }

    /// Moves by plain adjacent calendar days, not just days with a posted
    /// shift. The shift-days-only version confirmed live to trap you: once you
    /// swiped past today onto a later shift day, swiping back could never land
    /// back on today if today itself had no shift, since it was never a valid
    /// stop.
    ///
    /// Tracks the finger live via `pageOffset` instead of only reacting on
    /// release — the actual day change still only commits on release, but the
    /// content visibly follows the drag the whole way, which is most of what
    /// reads as "native" here. The release decision uses velocity as well as
    /// distance, same as a native page swipe: a fast short flick commits just
    /// like a slow long drag does, instead of requiring a fixed travel
    /// distance regardless of how the gesture was actually thrown.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) else { return }
                if pendingTargetDate == nil {
                    let direction = horizontal < 0 ? 1 : -1
                    pendingDirection = direction
                    pendingTargetDate = calendar.date(byAdding: .day, value: direction, to: selectedDate)
                }
                pageOffset = horizontal
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical), let target = pendingTargetDate else {
                    cancelPush()
                    return
                }

                let velocity = value.predictedEndTranslation.width - horizontal
                let shouldCommit = abs(horizontal) > 60 || abs(velocity) > 300
                guard shouldCommit else {
                    cancelPush()
                    return
                }
                commitPush(to: target)
            }
    }

    /// Continues the SAME motion the rest of the way (rather than snapping)
    /// so the finger lifting off doesn't visibly change the animation, then
    /// commits `selectedDate` once the push has fully landed.
    private func commitPush(to target: Date) {
        withAnimation(daySwipeAnimation, completionCriteria: .removed) {
            pageOffset = pendingDirection > 0 ? -pageWidth : pageWidth
        } completion: {
            selectedDate = target
            if !calendar.isDate(target, equalTo: displayedMonth, toGranularity: .month) {
                displayedMonth = target
            }
            pageOffset = 0
            pendingTargetDate = nil
        }
    }

    private func cancelPush() {
        withAnimation(daySwipeAnimation, completionCriteria: .removed) {
            pageOffset = 0
        } completion: {
            pendingTargetDate = nil
        }
    }

    /// Programmatic equivalent of a completed swipe (tap on a day cell,
    /// jump-to-today) — same dual-pane push, just driven by an immediate
    /// animation instead of a drag.
    private func navigate(to target: Date) {
        guard !calendar.isDate(target, inSameDayAs: selectedDate), pendingTargetDate == nil else { return }
        pendingDirection = target >= selectedDate ? 1 : -1
        pendingTargetDate = target
        commitPush(to: target)
    }
}

/// A request for Home to move the calendar by whole months.
struct MonthCommand: Equatable {
    let id = UUID()
    let delta: Int
}

/// A request for Home to show one day.
struct HomeJump: Equatable {
    let id = UUID()
    let date: Date
}

/// Shifts grouped by calendar day, each day's list already in start-time order.
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

private struct DayCell: View {
    let day: Date
    let isToday: Bool
    let isSelected: Bool
    let isHolidayPay: Bool
    let isWeekend: Bool
    let accentColors: [Color]
    let jobs: [String]
    let scale: CGFloat

    @ObservedObject private var theme = ThemeManager.shared

    private var circleSize: CGFloat { 38 * scale }

    private var calendar: Calendar { Calendar.current }

    /// Selected day always wins the accent-colored circle — including when
    /// the selection IS today. Today falls back to a plain gray circle when some
    /// OTHER day is selected — a quiet marker rather than competing with the
    /// actual selection. A Whole Foods holiday-pay day gets a tiny star beside
    /// its number instead of a fill.
    ///
    /// The circle is ONE constant size regardless of state, so moving the
    /// selection never makes circles grow or shrink; only the fill changes.
    /// Weekend numbers are dimmed, as in Apple Calendar.
    var body: some View {
        VStack(spacing: 5) {
            Text("\(calendar.component(.day, from: day))")
                .font(.title3.weight(isToday || isSelected ? .bold : .medium))
                .minimumScaleFactor(0.7)
                .foregroundStyle(numberStyle)
                .frame(width: circleSize, height: circleSize)
                .background {
                    if isSelected {
                        Circle().fill(theme.current.accent)
                    } else if isToday && theme.highContrast {
                        // Selected is a solid black/white disc, so today is a ring.
                        Circle().strokeBorder(Color(.label), lineWidth: 2.5)
                    } else if isToday {
                        Circle().fill(Color(.label))
                    }
                }

            indicator
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Color alone never carries the meaning: VoiceOver gets the full date,
    /// what kind of work is scheduled, and the day's special status in words.
    private var accessibilityDescription: String {
        var parts = [day.formatted(.dateTime.weekday(.wide).month(.wide).day())]
        if isToday { parts.append(String(localized: "Today")) }
        if isHolidayPay { parts.append(String(localized: "Holiday pay")) }
        parts.append(contentsOf: jobs)
        return parts.joined(separator: ", ")
    }

    private var numberStyle: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Color.onFill(theme.current.accent)) }
        if isToday { return theme.highContrast ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color(.systemBackground)) }
        return isWeekend ? AnyShapeStyle(Color.primary.opacity(0.7)) : AnyShapeStyle(.primary)
    }

    /// Under the number: a dot for one kind of work, a small multi-color pill when
    /// there's more, and a tiny star for holiday pay. On a day with both, the star
    /// sits beside the dot and turns white (red in high contrast) so it reads
    /// against the work color rather than blending into it.
    private var indicator: some View {
        HStack(spacing: 4) {
            workMarker
            if isHolidayPay {
                Image(systemName: "star.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(starColor)
            }
        }
        .frame(height: 8)
    }

    private var starColor: Color {
        let hasWork = !accentColors.isEmpty
        if hasWork {
            return theme.highContrast ? .red : .primary
        }
        return theme.highContrast ? Color.primary : Color.readable(theme.current.holidayPay, minimumContrast: 3)
    }

    @ViewBuilder
    private var workMarker: some View {
        if accentColors.count == 1 {
            Circle().fill(accentColors[0]).frame(width: 6, height: 6)
        } else if accentColors.count > 1 {
            HStack(spacing: 0) {
                ForEach(Array(accentColors.enumerated()), id: \.offset) { _, color in
                    Rectangle().fill(color)
                }
            }
            .frame(width: 22, height: 6)
            .clipShape(Capsule())
        }
    }
}

private struct DayEventRow: View {
    let shift: Shift

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(shift.accentColor(theme: theme.current))
                .frame(width: 4)
                .clipShape(.rect(cornerRadius: 2))

            VStack(alignment: .leading, spacing: 4) {
                Text(shift.job)
                    .font(.headline)
                if let location = shift.location {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(shift.startTime.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.weight(.semibold))
                Text(shift.endTime.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
    }
}

/// Left-to-right layout that wraps onto a new row when the next item won't fit.
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
