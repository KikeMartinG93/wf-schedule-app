import SwiftUI

struct RootView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showingWelcome = false
    @State private var whatsNewItems: [WhatsNew.Item] = []
    @State private var showingWhatsNew = false

    var body: some View {
        MainTabView()
        .onAppear {
            if hasSeenWelcome {
                // An update: summarize what changed since the last build they opened.
                let pending = WhatsNew.pendingItems()
                if !pending.isEmpty {
                    whatsNewItems = pending
                    showingWhatsNew = true
                }
                // A fresh process always starts logged out (the webview can't
                // survive relaunch) — try to resume silently from cookies saved
                // at the last successful login before falling back to the
                // sign-in card. See SessionManager's doc comment.
                if sessionManager.state != .authenticated {
                    Task { await sessionManager.attemptCookieRestore() }
                }
            } else {
                // A fresh install gets the welcome, which already covers everything.
                showingWelcome = true
                WhatsNew.markSeen()
            }
        }
        .sheet(isPresented: $showingWelcome) {
            WelcomeView {
                hasSeenWelcome = true
                showingWelcome = false
                Task { await AppBootstrap.run() }
            }
        }
        .sheet(isPresented: $showingWhatsNew) {
            WhatsNewView(items: whatsNewItems) {
                WhatsNew.markSeen()
                showingWhatsNew = false
            }
        }
    }
}

private enum AppTab: Hashable {
    case home, list, alerts, settings
}

private struct MainTabView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @State private var selectedTab: AppTab = .home
    @State private var homeResetToken = 0
    @State private var showingLogin = false
    @State private var loginBackend: SessionBackend = .innerview
    @State private var showingBreaks = false
    @State private var homeJump: HomeJump?
    @State private var monthCommand: MonthCommand?
    /// The system tab bar collapses into a round button while a list scrolls down;
    /// this follows it so the shift bar can drop into the same row beside that
    /// button, and float back up when the tab bar opens again.
    @State private var barMinimized = false
    @ObservedObject private var theme = ThemeManager.shared

    private static let tabBarHeight: CGFloat = 49

    private var isAuthenticated: Bool { sessionManager.state == .authenticated }

    /// Only while a returning user's session might still be restorable and
    /// they aren't already signing in by hand. This probe reloads the UKG Pro
    /// sign-in page, so it's only for someone whose session is a UKG one —
    /// Innerview Login resumes through `SessionManager.attemptCookieRestore`.
    private var shouldProbeForSession: Bool {
        !isAuthenticated && SessionManager.hasSignedInBefore && !showingLogin
            && SessionManager.preferredBackend == .ukg
    }

    var body: some View {
        TabView(selection: selectionBinding) {
            Tab("Home", systemImage: "calendar", value: AppTab.home) {
                HomeCalendarView(resetToken: homeResetToken, onSignIn: { backend in
                    loginBackend = backend
                    showingLogin = true
                }, jump: homeJump, monthCommand: monthCommand)
            }
            Tab("List", systemImage: "list.bullet", value: AppTab.list) {
                ScheduleListView()
            }
            Tab("Alerts", systemImage: "bell.fill", value: AppTab.alerts) {
                AlertsView(isActive: selectedTab == .alerts)
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        // The system tab bar, like Gymship: it collapses into a round button when a
        // list scrolls, leaving room for the shift countdown beside it.
        .tabBarMinimizeBehavior(.onScrollDown)
        // `.tint()` on TabView is the standard way to color its selected-item
        // state; it also becomes the default tint for each tab's own content
        // (buttons, toggles, etc.) unless that view sets its own tint.
        .tint(theme.current.readableAccent)
        // One bar shared by every tab (so it can morph between them), floated above
        // the tab bar. The lift is the floating tab bar's height.
        .overlay(alignment: .bottom) {
            shiftBar(showsMonthArrows: selectedTab == .home && !barMinimized)
                // Minimized: sit on the tab bar's own row, to the right of its round button.
                .padding(.leading, barMinimized ? 62 : 0)
                .padding(.bottom, barMinimized ? -11 : Self.tabBarHeight)
                .animation(.spring(response: 0.28, dampingFraction: 0.85), value: barMinimized)
        }
        // The tab bar's real state, read from UIKit: it also opens when its round
        // button is tapped or a tab is picked, which no scroll tracking could see.
        .background { TabBarMinimizedObserver(isMinimized: $barMinimized).allowsHitTesting(false) }
        // Home is the first tab, but the only sync trigger used to live in the
        // List tab's own task, so a fresh install showed an empty Home calendar
        // until List was opened. MainTabView only exists once authenticated, so
        // this can't burn the auto-sync throttle window before login.
        .task {
            if isAuthenticated { try? await ScheduleSyncCoordinator.runSync() }
        }
        .onChange(of: sessionManager.state) { _, newState in
            guard newState == .authenticated else { return }
            showingLogin = false
            Task { try? await ScheduleSyncCoordinator.runSync(force: true) }
        }
        // Breaks has no tab of its own: it opens from the countdown pill during a
        // shift, and from tapping a break widget or Live Activity.
        .sheet(isPresented: $showingBreaks) {
            BreaksView()
                .tint(theme.current.readableAccent)
                .presentationDragIndicator(.visible)
        }
        .onOpenURL { url in
            if url.scheme == "wfschedule", url.host == "breaks" { showingBreaks = true }
        }
        .sheet(isPresented: $showingLogin) {
            Group {
                if loginBackend == .ukg { UKGLoginView() } else { LoginView() }
            }
            .tint(theme.current.readableAccent)
            .presentationDragIndicator(.visible)
        }
        .background {
            if shouldProbeForSession { SessionRestoreProbe() }
        }
    }

    /// The bar above the tab bar: three glass buttons on Home, one pill elsewhere.
    private func shiftBar(showsMonthArrows: Bool) -> some View {
        ShiftCountdownAccessory(
            onTap: { target in
                switch target {
                case .breaks:
                    showingBreaks = true
                case .shift(let date):
                    selectedTab = .home
                    homeJump = HomeJump(date: date)
                }
            },
            onPreviousMonth: showsMonthArrows ? { monthCommand = MonthCommand(delta: -1) } : nil,
            onNextMonth: showsMonthArrows ? { monthCommand = MonthCommand(delta: 1) } : nil
        )
    }

    /// Tapping the Home tab while already on Home doesn't change
    /// `selectedTab` (same value in, same value out), so `.onChange(of:)` on
    /// the selection would never fire for that tap — that's the standard
    /// "tap the active tab to jump home" gesture, and detecting it needs the
    /// binding's own `set`, which runs on every tap regardless of whether the
    /// value actually changes.
    private var selectionBinding: Binding<AppTab> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == .home && selectedTab == .home {
                    homeResetToken += 1
                }
                selectedTab = newValue
            }
        )
    }
}

/// Reports whether the system tab bar is collapsed into its round button, by
/// looking at which of the tab bar's platters is showing.
private struct TabBarMinimizedObserver: UIViewRepresentable {
    @Binding var isMinimized: Bool

    func makeUIView(context: Context) -> UIView { UIView() }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.binding = $isMinimized
        context.coordinator.start(from: view)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var binding: Binding<Bool>?
        private var timer: Timer?
        private weak var anchor: UIView?
        func start(from view: UIView) {
            anchor = view
            guard timer == nil else { return }
            // `.common`, not the default mode: the default one is paused while a
            // scroll view is tracking, which is exactly when this needs to run.
            let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
                self?.poll()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        private func poll() {
            guard let window = anchor?.window, let bar = Self.tabBar(in: window) else { return }
            let platters = bar.allSubviews.filter { String(describing: type(of: $0)).contains("PlatterView") }
            // Each direction is called by the platter that appears first: collapsing
            // by the round one showing, opening by the full-width one showing (the
            // round one lingers a moment while it opens, so it can't decide that).
            let roundShowing = platters.contains { !$0.isHidden && $0.bounds.width < 100 }
            let wideShowing = platters.contains { !$0.isHidden && $0.bounds.width > 100 }
            var minimized = binding?.wrappedValue ?? false
            if minimized, wideShowing { minimized = false }
            else if !minimized, roundShowing { minimized = true }
            if binding?.wrappedValue != minimized { binding?.wrappedValue = minimized }
        }

        private static func tabBar(in view: UIView) -> UITabBar? {
            if let bar = view as? UITabBar { return bar }
            for sub in view.subviews { if let bar = tabBar(in: sub) { return bar } }
            return nil
        }

        deinit { timer?.invalidate() }
    }
}

private extension UIView {
    var allSubviews: [UIView] { subviews + subviews.flatMap(\.allSubviews) }
}
