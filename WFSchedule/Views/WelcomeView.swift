import SwiftUI

/// First-launch welcome, laid out like Apple's own "Welcome to…" / "What's New"
/// sheets: a big two-line title, a list of feature rows (accent-colored symbol,
/// bold headline, secondary description), and a full-width glass button pinned
/// to the bottom. Symbols use the active theme accent instead of a rainbow so it
/// matches whichever color theme is selected.
struct WelcomeView: View {
    var buttonTitle: LocalizedStringKey = "Continue"
    let onContinue: () -> Void

    @ObservedObject private var theme = ThemeManager.shared
    @State private var appeared = false

    private struct Feature: Identifiable {
        let id = UUID()
        let symbol: String
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
    }

    private let features: [Feature] = [
        Feature(symbol: "calendar",
                title: "Your schedule, always current",
                detail: "Sign in with UKG once and your shifts sync in the background, on a month calendar or a simple list."),
        Feature(symbol: "bell.badge.fill",
                title: "Know the moment it changes",
                detail: "Get notified when a shift is added, moved, or removed, plus a reminder before each one starts."),
        Feature(symbol: "calendar.badge.plus",
                title: "Lives in Apple Calendar",
                detail: "Shifts appear in their own Work Schedule calendar on all your Apple devices."),
        Feature(symbol: "barcode",
                title: "Discount barcode on your wrist",
                detail: "Save your TM ID in Settings and it shows up as an Apple Watch complication."),
        Feature(symbol: "lock.rectangle.stack.fill",
                title: "Next shift at a glance",
                detail: "Add the Next Shift widget to your Lock Screen to see what's coming and how long until it starts."),
        Feature(symbol: "paintpalette.fill",
                title: "Make it yours",
                detail: "Pick a color theme in Settings and the whole app follows."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(spacing: 4) {
                    Text("Welcome to")
                        .font(.largeTitle.weight(.bold))
                    Text("WF Schedule")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(theme.current.readableAccent)
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 32)

                VStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(features.enumerated()), id: \.element.id) { index, feature in
                        row(feature)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 14)
                            .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.08 * Double(index)), value: appeared)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .overlay(alignment: .topTrailing) {
            Menu {
                Button {
                    DemoMode.set(true)
                    onContinue()
                } label: {
                    Label("Demo Mode", systemImage: "sparkles")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .padding(20)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Options")
        }
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 10) {
                Text("Your schedule is stored only on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(action: onContinue) {
                    Text(buttonTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(theme.current.buttonFill)
                .controlSize(.large)

                Button {
                    DemoMode.set(true)
                    onContinue()
                } label: {
                    Label("Explore Demo Mode", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.current.readableAccent)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .interactiveDismissDisabled()
        .onAppear { appeared = true }
    }

    private func row(_ feature: Feature) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: feature.symbol)
                .font(.title)
                .foregroundStyle(theme.current.readableAccent)
                .frame(width: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.headline)
                Text(feature.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
