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
    case home, timeline, alerts, settings
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
    @State private var timelineRefreshTrigger = 0
    @State private var isSyncingTimeline = false
    @State private var alertsFilter: AlertsFilter = .unread
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
            Tab("Timeline", systemImage: "list.bullet", value: AppTab.timeline) {
                ScheduleListView(refreshTrigger: timelineRefreshTrigger, isSyncing: $isSyncingTimeline)
            }
            Tab("Alerts", systemImage: "bell.fill", value: AppTab.alerts) {
                AlertsView(isActive: selectedTab == .alerts, filter: $alertsFilter)
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView()
            }
        }
        // Keep the tab bar stable and fixed at the bottom while scrolling.
        .tabBarMinimizeBehavior(.never)
        // `.tint()` on TabView is the standard way to color its selected-item
        // state; it also becomes the default tint for each tab's own content
        // (buttons, toggles, etc.) unless that view sets its own tint.
        .tint(theme.current.readableAccent)
        // One bar shared by every tab (so it can morph between them), floated above
        // the tab bar. The lift is the floating tab bar's height.
        .overlay(alignment: .bottom) {
            shiftBar(for: selectedTab)
                .padding(.bottom, Self.tabBarHeight)
        }
        // Home is the first tab, but the only sync trigger used to live in the
        // Timeline tab's own task, so a fresh install showed an empty Home calendar
        // until Timeline was opened. MainTabView only exists once authenticated, so
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

    /// The bar above the tab bar: morphs between arrows, refresh, and check/history buttons.
    private func shiftBar(for tab: AppTab) -> some View {
        let prevAction: (() -> Void)? = (tab == .home) ? { monthCommand = MonthCommand(delta: -1) } : nil
        let rightConfig: ShiftCountdownAccessory.RightButton?
        switch tab {
        case .home:
            rightConfig = ShiftCountdownAccessory.RightButton(
                symbol: "chevron.right",
                label: "Next month",
                action: { monthCommand = MonthCommand(delta: 1) }
            )
        case .timeline:
            rightConfig = ShiftCountdownAccessory.RightButton(
                symbol: "arrow.clockwise",
                label: "Refresh",
                action: { timelineRefreshTrigger += 1 },
                isLoading: isSyncingTimeline,
                isDisabled: isSyncingTimeline
            )
        case .alerts:
            switch alertsFilter {
            case .unread:
                rightConfig = ShiftCountdownAccessory.RightButton(
                    symbol: "checkmark",
                    label: "Mark all as viewed",
                    action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            ChangeLogStore.shared.markAllSeen()
                            alertsFilter = .history30
                        }
                    }
                )
            case .history30:
                rightConfig = ShiftCountdownAccessory.RightButton(
                    symbol: "clock.arrow.circlepath",
                    label: "30 days history",
                    action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            alertsFilter = .history60
                        }
                    },
                    badgeText: "30"
                )
            case .history60:
                rightConfig = ShiftCountdownAccessory.RightButton(
                    symbol: "clock.arrow.circlepath",
                    label: "60 days history",
                    action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            alertsFilter = .history90
                        }
                    },
                    badgeText: "60"
                )
            case .history90:
                rightConfig = ShiftCountdownAccessory.RightButton(
                    symbol: "clock.arrow.circlepath",
                    label: "90 days history",
                    action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            alertsFilter = .unread
                        }
                    },
                    badgeText: "90"
                )
            }
        case .settings:
            rightConfig = nil
        }

        return ShiftCountdownAccessory(
            onTap: { target in
                switch target {
                case .breaks:
                    showingBreaks = true
                case .shift(let date):
                    selectedTab = .home
                    homeJump = HomeJump(date: date)
                }
            },
            onPreviousMonth: prevAction,
            rightButton: rightConfig
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
