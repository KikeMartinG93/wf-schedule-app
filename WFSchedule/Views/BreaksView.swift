import SwiftUI
import WidgetKit

/// Enter one to three breaks (time + length) and get a live countdown to the
/// next one, in the app and on the widgets / watch complication.
struct BreaksView: View {
    @State private var plan = BreakStore.load()
    @State private var pulse = false
    @State private var fanOutTask: Task<Void, Never>?
    @AppStorage("calcShiftStart") private var calcStartMinutes = 9 * 60
    @AppStorage("calcShiftEnd") private var calcEndMinutes = 17 * 60 + 30
    @ObservedObject private var theme = ThemeManager.shared

    private let durations = [10, 15, 20, 30, 45, 60]

    /// Height of the countdown and editor cards; the sheet's first stop is sized to
    /// exactly that, so the calculator stays below the fold until you swipe up.
    @State private var topHeight: CGFloat = 320
    @State private var expanded = false
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    /// Sheet chrome around the cards: drag indicator, top padding and the home-indicator inset.
    private let sheetChrome: CGFloat = 30

    private var compactDetent: PresentationDetent { .height(topHeight + sheetChrome) }
    /// With VoiceOver on there is only the full sheet, so the calculator is always there.
    private var showCalculator: Bool { expanded || voiceOver }

    private var detentSelection: Binding<PresentationDetent> {
        Binding(
            get: { showCalculator ? .large : compactDetent },
            set: { expanded = ($0 == .large) }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 16) {
                            heroCard
                            editor
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0 }

                        calculator
                            .opacity(showCalculator ? 1 : 0)
                            .offset(y: showCalculator ? 0 : 24)
                            .allowsHitTesting(showCalculator)
                            .accessibilityHidden(!showCalculator)
                    }
                    .padding(.horizontal)
                    .padding(.top, 22)
                    .padding(.bottom, 80)
                    .animation(.snappy(duration: 0.3), value: showCalculator)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
            // Two stops: the countdown and your breaks first, the calculator on swipe up.
            // With VoiceOver on there is just the full sheet, so nothing is hidden.
            .presentationDetents(voiceOver ? [.large] : [compactDetent, .large], selection: detentSelection)
            .presentationContentInteraction(.resizes)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                plan = BreakStore.load()
                if !UIAccessibility.isReduceMotionEnabled {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
                }
            }
            .onChange(of: plan) {
                // Persist right away so nothing is lost, but hold the fan-out
                // (widget reloads, watch message, Live Activity) until edits pause:
                // spinning a time-picker wheel changes the plan dozens of times.
                BreakStore.save(plan, reloadWidgets: false)
                scheduleFanOut()
            }
            .onDisappear { flushFanOut() }
        }
    }

    // MARK: - Syncing

    private func scheduleFanOut() {
        fanOutTask?.cancel()
        fanOutTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            flushFanOut()
        }
    }

    private func flushFanOut() {
        guard fanOutTask != nil else { return }
        fanOutTask?.cancel()
        fanOutTask = nil
        WidgetCenter.shared.reloadAllTimelines()
        BarcodePhoneSync.shared.send(BarcodeStore.value)
    }

    // MARK: - Countdown

    private var heroCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let status = plan.status(at: context.date)
            VStack(alignment: .leading, spacing: 12) {
                switch status {
                case .none:
                    Label("No breaks set", systemImage: "cup.and.saucer")
                        .font(.headline)
                    Text("Add your breaks below to start a countdown.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                case .allTaken:
                    Label("All breaks taken", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(theme.highContrast ? Color.primary : Color.green)
                case .upcoming(let due, let number, let duration):
                    countdown(label: "Next break", due: due, number: number, duration: duration,
                              remaining: due.timeIntervalSince(context.date), overdue: false)
                case .overdue(let due, let number, let duration):
                    countdown(label: "Break overdue", due: due, number: number, duration: duration,
                              remaining: 0, overdue: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            .highContrastOutline(cornerRadius: 24)
        }
    }

    private func countdown(label: LocalizedStringKey, due: Date, number: Int, duration: Int,
                           remaining: TimeInterval, overdue: Bool) -> some View {
        let color = BreakStyle.color(remaining: overdue ? nil : remaining)
        let textColor = Color.readable(color)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(overdue ? textColor : .secondary)
                Spacer()
                Text(due, style: .timer)
                    .font(.system(.largeTitle, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(overdue ? textColor : .primary)
            }
            BreakBar(fill: overdue ? 1 : BreakStyle.fill(remaining: remaining), color: color)
                .frame(height: 16)
                .opacity(overdue && pulse ? 0.35 : 1)
            HStack {
                Text("Break \(number) · \(duration) min")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    markTaken(number: number)
                } label: {
                    Label("Mark as taken", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.glassProminent)
                .tint(theme.current.buttonFill)
            }
        }
    }

    // MARK: - Editing

    private var countBinding: Binding<Int> {
        Binding(
            get: { plan.slots.count },
            set: { newCount in
                withAnimation(.snappy(duration: 0.3)) {
                    while plan.slots.count < newCount {
                        plan.slots.append(BreakPlan.defaultSlot(index: plan.slots.count))
                    }
                    if plan.slots.count > newCount {
                        plan.slots.removeLast(plan.slots.count - newCount)
                    }
                }
            }
        )
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your breaks")
                .font(.headline)

            Stepper(value: countBinding, in: 0...7) {
                Text("Number of breaks: \(plan.slots.count)")
                    .font(.subheadline)
            }

            ForEach($plan.slots) { $slot in
                slotRow($slot)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }

            if !plan.slots.isEmpty {
                Text("Times repeat every day. Mark a break as taken to stop its countdown; it resets tomorrow.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .highContrastOutline(cornerRadius: 24)
    }

    private func slotRow(_ slot: Binding<BreakSlot>) -> some View {
        let number = (plan.slots.firstIndex { $0.id == slot.wrappedValue.id } ?? 0) + 1
        return HStack(spacing: 8) {
            Text("Break \(number)")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize()

            DatePicker("", selection: timeBinding(slot), displayedComponents: .hourAndMinute)
                .labelsHidden()

            Picker("", selection: slot.durationMinutes) {
                ForEach(durations, id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }
            .labelsHidden()
            .fixedSize()
            .tint(.secondary)

            Spacer(minLength: 0)

            Button {
                toggleTaken(slot)
            } label: {
                Image(systemName: slot.wrappedValue.isTaken(on: Date()) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(slot.wrappedValue.isTaken(on: Date()) ? theme.current.readableAccent : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Taken")
        }
    }

    private func timeBinding(_ slot: Binding<BreakSlot>) -> Binding<Date> {
        Binding(
            get: {
                let calendar = Calendar.current
                return calendar.date(byAdding: .minute, value: slot.wrappedValue.minutesFromMidnight,
                                     to: calendar.startOfDay(for: Date())) ?? Date()
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                slot.wrappedValue.minutesFromMidnight = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                slot.wrappedValue.takenOn = nil
            }
        )
    }

    private func toggleTaken(_ slot: Binding<BreakSlot>) {
        slot.wrappedValue.takenOn = slot.wrappedValue.isTaken(on: Date()) ? nil : Calendar.current.startOfDay(for: Date())
    }

    private func markTaken(number: Int) {
        guard plan.slots.indices.contains(number - 1) else { return }
        plan.slots[number - 1].takenOn = Calendar.current.startOfDay(for: Date())
    }

    // MARK: - Break calculator

    private var shiftMinutes: Int {
        BreakCalculator.shiftMinutes(startMinutes: calcStartMinutes, endMinutes: calcEndMinutes)
    }

    private var requirement: BreakRequirement {
        BreakCalculator.requirement(forShiftHours: Double(shiftMinutes) / 60)
    }

    private func minutesBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                let calendar = Calendar.current
                return calendar.date(byAdding: .minute, value: minutes.wrappedValue, to: calendar.startOfDay(for: Date())) ?? Date()
            },
            set: { newValue in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    private var calculator: some View {
        let need = requirement
        return VStack(alignment: .leading, spacing: 14) {
            Text("Break calculator")
                .font(.headline)

            HStack {
                DatePicker("Shift start", selection: minutesBinding($calcStartMinutes), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Text("–")
                    .foregroundStyle(.secondary)
                DatePicker("Shift end", selection: minutesBinding($calcEndMinutes), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Spacer(minLength: 0)
                Button("Use my next shift") { useNextShift() }
                    .font(.footnote)
                    .buttonStyle(.borderless)
            }

            Text("Shift length: \(durationText(shiftMinutes))")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                resultRow(symbol: "cup.and.saucer.fill",
                          title: "Paid rest breaks (10 min)",
                          count: need.restBreaks)
                resultRow(symbol: "fork.knife",
                          title: "Unpaid meal periods (30 min)",
                          count: need.mealPeriods)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(mealSummary(need))
                Text(secondRestSummary(need))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            if need.restBreaks + need.mealPeriods > 0 {
                Button {
                    plan.slots = BreakCalculator.slots(startMinutes: calcStartMinutes, shiftMinutes: shiftMinutes, requirement: need)
                } label: {
                    Label("Use these in my break timer", systemImage: "timer")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(theme.current.buttonFill)
            }

            DisclosureGroup("Break chart") {
                chart
            }
            .font(.subheadline)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .highContrastOutline(cornerRadius: 24)
    }

    private func resultRow(symbol: String, title: LocalizedStringKey, count: Int) -> some View {
        HStack {
            Image(systemName: symbol)
                .frame(width: 24)
                .foregroundStyle(theme.current.readableAccent)
            Text(title)
                .font(.subheadline)
            Spacer()
            Text("\(count)")
                .font(.title3.weight(.bold))
                .monospacedDigit()
        }
    }

    private func mealSummary(_ need: BreakRequirement) -> LocalizedStringKey {
        if need.mealPeriods == 0 { return "No meal period is required for a shift this short." }
        if need.mealMayBeWaived { return "A meal period is required, but you and your manager can agree to skip it since your shift is 6 hours or less." }
        return need.mealPeriods == 1 ? "You must take 1 unpaid 30-minute meal period." : "You must take \(need.mealPeriods) unpaid 30-minute meal periods."
    }

    private func secondRestSummary(_ need: BreakRequirement) -> LocalizedStringKey {
        need.restBreaks >= 2 ? "You get a second 10-minute rest break." : "No second 10-minute rest break for this shift."
    }

    private func durationText(_ minutes: Int) -> String {
        let hours = minutes / 60, remainder = minutes % 60
        return remainder == 0 ? String(localized: "\(hours) h") : String(localized: "\(hours) h \(remainder) min")
    }

    private func useNextShift() {
        guard let shift = ShiftLibrary.shifts(on: Date()).first ?? ShiftLibrary.nextShift() else { return }
        let calendar = Calendar.current
        func minutes(_ date: Date) -> Int {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
        calcStartMinutes = minutes(shift.startTime)
        calcEndMinutes = minutes(shift.endTime)
    }

    private var chart: some View {
        let rows: [(String, Int, Int)] = [("> 2 h", 1, 0), ("> 5 h", 1, 1), ("> 6 h", 2, 1), ("> 10 h", 3, 2), ("> 14 h", 4, 3)]
        return VStack(spacing: 6) {
            HStack {
                Text("Shift")
                Spacer()
                Text("Rest")
                    .frame(width: 60)
                Text("Meal")
                    .frame(width: 60)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(rows, id: \.0) { row in
                HStack {
                    Text(verbatim: row.0)
                    Spacer()
                    Text("\(row.1)").frame(width: 60)
                    Text("\(row.2)").frame(width: 60)
                }
                .font(.subheadline)
            }
        }
        .padding(.top, 6)
    }
}
