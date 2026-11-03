import SwiftUI

/// Asks how the associate is paid, and for Direct Deposit which biweekly weekday.
/// Used at the end of first-launch onboarding and anytime from Settings.
struct PaySetupView: View {
    var showsSkip: Bool = false
    var onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var theme = ThemeManager.shared
    @State private var method: PaymentMethod? = PayPreferences.method
    @State private var weekday: PaydayWeekday? = PayPreferences.weekday
    @State private var step: Step = PayPreferences.method == .directDeposit ? .weekday : .method

    private enum Step {
        case method
        case weekday
    }

    private var canContinue: Bool {
        switch step {
        case .method: method != nil
        case .weekday: weekday != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(step == .method ? "How do you get paid?" : "When is Direct Deposit?")
                            .font(.largeTitle.weight(.bold))
                        Text(step == .method
                             ? "We’ll mark Payday on your schedule if you use Direct Deposit."
                             : "Whole Foods Direct Deposit is every other week. Pick the day yours lands.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 28)

                    if step == .method {
                        VStack(spacing: 12) {
                            ForEach(PaymentMethod.allCases) { option in
                                choiceCard(
                                    title: option.title,
                                    detail: option == .directDeposit
                                        ? String(localized: "Paid every other week by bank deposit.")
                                        : String(localized: "Paid by paper check — no payday markers."),
                                    symbol: option == .directDeposit ? "building.columns.fill" : "doc.text.fill",
                                    selected: method == option
                                ) {
                                    method = option
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            ForEach(PaydayWeekday.allCases) { option in
                                let next = option.anchorPayday
                                let period = PaydayCalendar.periodDescription(forPayday: next) ?? ""
                                let nextLabel = next.formatted(.dateTime.month(.abbreviated).day().year())
                                choiceCard(
                                    title: option.title,
                                    detail: "Next payday \(nextLabel) · period \(period)",
                                    symbol: "calendar.badge.clock",
                                    selected: weekday == option
                                ) {
                                    weekday = option
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }

            VStack(spacing: 10) {
                Button(action: advance) {
                    Text(primaryTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(theme.current.buttonFill)
                .controlSize(.large)
                .disabled(!canContinue)

                if showsSkip || step == .weekday {
                    Button(step == .weekday ? "Back" : "Skip for now") {
                        if step == .weekday {
                            withAnimation { step = .method }
                        } else {
                            PayPreferences.markSkipped()
                            finish()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.current.readableAccent)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .navigationTitle("Payday")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(showsSkip)
    }

    private var primaryTitle: LocalizedStringKey {
        switch step {
        case .method:
            method == .check ? "Done" : "Continue"
        case .weekday:
            "Done"
        }
    }

    private func advance() {
        guard let method else { return }
        if step == .method {
            if method == .check {
                PayPreferences.save(method: .check, weekday: nil)
                Task { try? CalendarSyncService().syncPaydayEvents() }
                finish()
            } else {
                withAnimation { step = .weekday }
            }
            return
        }
        guard let weekday else { return }
        PayPreferences.save(method: .directDeposit, weekday: weekday)
        Task { try? await syncPaydays() }
        finish()
    }

    private func finish() {
        onFinished()
        dismiss()
    }

    private func syncPaydays() async throws {
        let sync = CalendarSyncService()
        try await sync.requestAccess()
        try sync.syncPaydayEvents()
    }

    private func choiceCard(
        title: LocalizedStringKey,
        detail: String,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                ThemedGlyph(symbol: symbol, size: 36, font: .body.weight(.semibold))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? theme.current.readableAccent : Color.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? theme.current.readableAccent.opacity(0.12) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? theme.current.readableAccent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
