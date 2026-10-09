import SwiftUI

/// Release notes shown once after each update. Every TestFlight upload adds a
/// `Release` here (next `revision`) describing what changed since the previous
/// one. The app remembers the last revision it showed, so a tester who skips a
/// build sees the notes for everything they missed, newest first.
enum WhatsNew {
    struct Item: Identifiable {
        let id = UUID()
        let symbol: String
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
    }

    struct Release {
        let revision: Int
        let items: [Item]
    }

    /// Oldest first. To ship notes with a new build, append a release with the next revision.
    static let releases: [Release] = [
        Release(revision: 7, items: [
            Item(symbol: "timer",
                 title: "Break Live Activity",
                 detail: "Your break countdown now lives on the Lock Screen and in the Dynamic Island, turning red and counting up when a break is overdue."),
            Item(symbol: "eye.fill",
                 title: "Easier to read",
                 detail: "Higher-contrast colors, VoiceOver support for the calendar, and the rounded system font throughout the app."),
            Item(symbol: "bolt.fill",
                 title: "Faster and smoother",
                 detail: "The calendar, schedule and break editor do less work, so the app feels snappier and uses less battery."),
        ]),
        Release(revision: 8, items: [
            Item(symbol: "circle.dashed",
                 title: "Redesigned Break Timer widget",
                 detail: "A new ring design for the Home Screen, Lock Screen and Apple Watch that shifts from green to red as your break gets close."),
            Item(symbol: "circle.lefthalf.filled",
                 title: "High contrast and font choice",
                 detail: "New Readability settings: a high contrast mode that turns the whole app, widgets and Live Activity plain black, white and gray, and a switch between the rounded font and the standard system font."),
            Item(symbol: "clock.badge.fill",
                 title: "Shift countdown",
                 detail: "The tab bar now collapses as you scroll, with a live countdown beside it: time until your next shift, or until the shift you're on ends. Tap it during a shift to open your breaks, or any other time to jump to your next shift. Breaks no longer has its own tab."),
            Item(symbol: "rectangle.bottomhalf.inset.filled",
                 title: "A sleeker Breaks sheet",
                 detail: "Breaks now opens as a compact card with your countdown and your breaks. Swipe up to reveal the break calculator."),
            Item(symbol: "applewatch",
                 title: "Shift countdown on Apple Watch",
                 detail: "Open the Watch app to see the time until your next shift. During a shift the screen fills green, with a line that rises as the shift goes by until it reaches full capacity. Swipe up for your barcode."),
            Item(symbol: "sparkles",
                 title: "What's New",
                 detail: "Every update now opens with a summary like this one. You can find it again anytime in Settings."),
        ]),
        Release(revision: 9, items: [
            Item(symbol: "person.badge.key.fill",
                 title: "Staying signed in",
                 detail: "The app now saves your session itself, so it shouldn't ask you to sign in with your Amazon account every time you open it."),
        ]),
        Release(revision: 10, items: [
            Item(symbol: "person.crop.circle.badge.exclamationmark",
                 title: "Clearer when you're signed out",
                 detail: "Home now blurs the calendar and shows a sign-in button when your session needs attention — and only after actually checking, not on every launch."),
            Item(symbol: "bell.badge",
                 title: "Alerts clear themselves",
                 detail: "Switching away from Alerts now quietly marks what you saw as read. No more tapping each one or hitting Mark all as viewed."),
        ]),
        Release(revision: 11, items: [
            Item(symbol: "person.badge.key.fill",
                 title: "Innerview Login",
                 detail: "Sign in with your Whole Foods team member account and your schedule loads from Innerview. It's the new main sign-in; the Amazon sign-in is still in Settings as a backup."),
            Item(symbol: "cup.and.saucer.fill",
                 title: "Breaks on your Lock Screen",
                 detail: "The break Live Activity now only runs during your shift. Tap Start for a 10 minute break, a 30 minute lunch after four hours, and another break at six hours — each counts down on a bar that turns red near zero, then rings an alarm."),
        ]),
        Release(revision: 12, items: [
            Item(symbol: "person.text.rectangle.fill",
                 title: "Shows as Supervisor",
                 detail: "Shifts that Innerview lists as Customer Service Team, Front End now show up as Supervisor, with the Supervisor color."),
        ]),
        Release(revision: 13, items: [
            Item(symbol: "calendar",
                 title: "A softer calendar",
                 detail: "Home's month view drops the hard grid lines: every day is a soft rounded blob with its number and shift dot inside, tinted by the work you have that day."),
        ]),
        Release(revision: 14, items: [
            Item(symbol: "gearshape.fill",
                 title: "A neater Settings page",
                 detail: "Settings is now grouped into Account, Appearance, Display, Breaks, Barcode, Widgets, Demo and About, with an icon on every row."),
            Item(symbol: "rectangle.bottomthird.inset.filled",
                 title: "Smoother shift bar",
                 detail: "The shift bar now shrinks and expands faster with the tab bar, and it only floats back up once you're at the top of the list. Alerts no longer bounces when there's nothing to scroll."),
        ]),
        Release(revision: 15, items: [
            Item(symbol: "waveform.path",
                 title: "Animated fluid background",
                 detail: "Background gradients now slowly morph and breathe like Apple Music lyrics, bringing a dynamic, fluid ambiance to every screen."),
            Item(symbol: "sparkles",
                 title: "Full Demo Mode",
                 detail: "Explore all features — including break tools, operational role checklists, and sample shifts — directly from the new Demo Mode menu anytime you open the app or sign-in screens."),
        ]),
    ]

    static var latestRevision: Int { releases.last?.revision ?? 0 }

    private static let seenKey = "whatsNewSeenRevision"
    /// Testers already on the app before this screen existed last ran build 6.
    private static let legacyRevision = 6

    /// Items from every release newer than the last one shown, newest first.
    static func pendingItems() -> [Item] {
        let seen = UserDefaults.standard.object(forKey: seenKey) as? Int ?? legacyRevision
        return releases.filter { $0.revision > seen }.reversed().flatMap(\.items)
    }

    /// Items from the most recent release, for reopening from Settings.
    static func latestItems() -> [Item] { releases.last?.items ?? [] }

    static func markSeen() {
        UserDefaults.standard.set(latestRevision, forKey: seenKey)
    }
}

/// Same layout as the welcome sheet (and Apple's own What's New screens): a big
/// title, feature rows, and a full-width button pinned to the bottom.
struct WhatsNewView: View {
    let items: [WhatsNew.Item]
    var buttonTitle: LocalizedStringKey = "Continue"
    let onContinue: () -> Void

    @ObservedObject private var theme = ThemeManager.shared
    @State private var appeared = false

    private var versionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(spacing: 6) {
                    Text("What's New in")
                        .font(.largeTitle.weight(.bold))
                    Text("WF Schedule")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(theme.current.readableAccent)
                    Text(verbatim: versionText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 32)

                VStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        row(item)
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
        .safeAreaBar(edge: .bottom) {
            Button(action: onContinue) {
                Text(buttonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(theme.current.buttonFill)
            .controlSize(.large)
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .interactiveDismissDisabled()
        .onAppear { appeared = true }
    }

    private func row(_ item: WhatsNew.Item) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: item.symbol)
                .font(.title)
                .foregroundStyle(theme.current.readableAccent)
                .frame(width: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
