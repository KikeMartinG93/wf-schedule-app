import SwiftUI

/// The row above the tab bar: a live countdown to the next shift (or, during a
/// shift, to when it ends) between optional action buttons (e.g. month navigation,
/// timeline refresh, or marking alerts read). Each is its own glass button.
struct ShiftCountdownAccessory: View {
    /// What a tap on the countdown pill should do: during a shift, open the break tools;
    /// otherwise show the day of the next shift.
    enum Target {
        case breaks
        case shift(Date)
    }

    struct RightButton {
        let symbol: String
        let label: LocalizedStringKey
        let action: () -> Void
        var badgeText: String? = nil
        var isLoading: Bool = false
        var isDisabled: Bool = false
    }

    let onTap: (Target) -> Void
    /// The month arrows or action buttons on either side of the countdown. `nil` hides them.
    var onPreviousMonth: (() -> Void)? = nil
    var rightButton: RightButton? = nil

    /// Ties the glass shapes together so they morph into each other rather
    /// than fading in and out.
    @Namespace private var glass
    @State private var shifts: [Shift] = []
    @AppStorage(DemoMode.storageKey) private var demoMode = false

    init(
        onTap: @escaping (Target) -> Void,
        onPreviousMonth: (() -> Void)? = nil,
        rightButton: RightButton? = nil
    ) {
        self.onTap = onTap
        self.onPreviousMonth = onPreviousMonth
        self.rightButton = rightButton
    }

    init(
        onTap: @escaping (Target) -> Void,
        onPreviousMonth: (() -> Void)? = nil,
        onNextMonth: (() -> Void)? = nil
    ) {
        self.onTap = onTap
        self.onPreviousMonth = onPreviousMonth
        if let onNextMonth {
            self.rightButton = RightButton(symbol: "chevron.right", label: "Next month", action: onNextMonth)
        } else {
            self.rightButton = nil
        }
    }

    private enum Clock {
        case current(Shift)
        case next(Shift)
        case none
    }

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 8) {
                if let onPreviousMonth {
                    arrow("chevron.left", label: "Previous month", action: onPreviousMonth)
                        .glassEffectID("previous", in: glass)
                }
                TimelineView(.explicit(refreshDates)) { context in
                    let clock = clock(at: context.date)
                    content(for: clock, now: context.date)
                }
                .frame(maxWidth: .infinity)
                .frame(height: Self.height)
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("countdown", in: glass)

                if let rightButton {
                    rightButtonView(rightButton)
                        .glassEffectID("rightButton", in: glass)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if let badge = rightButton?.badgeText {
                Text(badge)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.onFill(ThemeManager.shared.current.accent))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(ThemeManager.shared.current.accent, in: Capsule())
                    .offset(x: 4, y: -4)
                    .allowsHitTesting(false)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 21)
        .padding(.bottom, 6)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: onPreviousMonth != nil)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: rightButton != nil)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: rightButton?.symbol)
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: rightButton?.badgeText)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: ScheduleStore.didChangeNotification)) { _ in reload() }
        .onChange(of: demoMode) { reload() }
    }

    private static let height: CGFloat = 46

    private func arrow(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline)
                .frame(width: Self.height, height: Self.height)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }

    private func rightButtonView(_ config: RightButton) -> some View {
        Button(action: config.action) {
            if config.isLoading {
                ProgressView()
                    .frame(width: Self.height, height: Self.height)
            } else {
                Image(systemName: config.symbol)
                    .font(.headline)
                    .frame(width: Self.height, height: Self.height)
                    .contentShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .disabled(config.isDisabled || config.isLoading)
        .accessibilityLabel(config.label)
    }

    // MARK: - State

    private func reload() {
        let latest = ScheduleStore.shared.load()?.shifts.filter { $0.kind != .timeOff } ?? []
        if latest != shifts { shifts = latest }
    }

    private func clock(at date: Date) -> Clock {
        if let current = shifts.filter({ $0.startTime <= date && date < $0.endTime }).max(by: { $0.endTime < $1.endTime }) {
            return .current(current)
        }
        if let next = shifts.filter({ $0.startTime > date }).min(by: { $0.startTime < $1.startTime }) {
            return .next(next)
        }
        return .none
    }

    /// The moments the display changes on its own: a shift starting or ending, and
    /// the point a countdown drops under a day (where it switches from "2 days,
    /// 3 hours" to a ticking timer).
    private var refreshDates: [Date] {
        let now = Date()
        var dates: Set<Date> = [now]
        for shift in shifts.filter({ $0.endTime > now }).sorted(by: { $0.startTime < $1.startTime }).prefix(6) {
            for date in [shift.startTime.addingTimeInterval(-86_400), shift.startTime, shift.endTime] where date > now {
                dates.insert(date)
            }
        }
        return dates.sorted()
    }

    // MARK: - Content

    @ViewBuilder
    private func content(for clock: Clock, now: Date) -> some View {
        switch clock {
        case .current(let shift):
            Button { onTap(.breaks) } label: {
                countdown(symbol: "figure.walk", label: "Shift ends in", target: shift.endTime, job: shift.job, now: now)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens your breaks")
        case .next(let shift):
            Button { onTap(.shift(shift.startTime)) } label: {
                countdown(symbol: "clock.fill", label: "Next shift in", target: shift.startTime, job: shift.job, now: now)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows your next shift")
        case .none:
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                Text("No upcoming shifts")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
        }
    }

    private func countdown(symbol: String, label: LocalizedStringKey, target: Date, job: String, now: Date) -> some View {
        let isInline = false
        return HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
            if isInline {
                remaining(target, now: now)
                    .font(.subheadline.weight(.semibold))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    remaining(target, now: now)
                        .font(.headline)
                }
                Spacer(minLength: 8)
                Text(verbatim: job)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Under a day: a ticking `h:mm:ss` timer. Longer: a coarse "2 days, 3 hours".
    @ViewBuilder
    private func remaining(_ target: Date, now: Date) -> some View {
        if target.timeIntervalSince(now) >= 86_400 {
            Text(target, style: .relative)
        } else {
            Text(target, style: .timer)
                .monospacedDigit()
        }
    }
}
