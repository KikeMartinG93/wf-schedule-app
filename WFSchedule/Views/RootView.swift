import SwiftUI

struct RootView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showingOnboarding = false
    @State private var showingPaySetup = false
    @State private var whatsNewItems: [WhatsNew.Item] = []
    @State private var showingWhatsNew = false

    var body: some View {
        MainTabView()
        .onAppear {
            // Returning installs must never get the first-run wizard again —
            // even if `hasSeenWelcome` was cleared by a reinstall-adjacent
            // container quirk. Only a truly empty install opens setup.
            if Self.isReturningInstall() {
                if !hasSeenWelcome { hasSeenWelcome = true }
                // An update: summarize what changed since the last build they opened.
                let pending = WhatsNew.pendingItems()
                if !pending.isEmpty {
                    whatsNewItems = pending
                    showingWhatsNew = true
                } else if !PayPreferences.isConfigured {
                    // Existing installs that never answered the pay questions.
                    showingPaySetup = true
                }
                // A fresh process always starts logged out (the webview can't
                // survive relaunch) — try to resume silently from cookies saved
                // at the last successful login before falling back to the
                // sign-in card. See SessionManager's doc comment.
                if sessionManager.state != .authenticated && scenePhase == .active && UIApplication.shared.applicationState != .background {
                    Task { await sessionManager.attemptCookieRestore() }
                }
            } else {
                // Brand-new install only: full setup wizard.
                showingOnboarding = true
                WhatsNew.markSeen()
            }
        }
        .fullScreenCover(isPresented: $showingOnboarding) {
            OnboardingWizardView {
                hasSeenWelcome = true
                showingOnboarding = false
                Task { await AppBootstrap.run() }
            }
        }
        .sheet(isPresented: $showingPaySetup) {
            PaySetupView(showsSkip: true) {
                showingPaySetup = false
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingWhatsNew) {
            WhatsNewView(items: whatsNewItems) {
                WhatsNew.markSeen()
                showingWhatsNew = false
                if !PayPreferences.isConfigured {
                    showingPaySetup = true
                }
            }
        }
    }

    /// True when this device already used the app — welcome, sign-in, pay,
    /// barcode, city, What's New, or CS Sup answers all count. Fresh installs
    /// have none of these.
    private static func isReturningInstall() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "hasSeenWelcome") { return true }
        if SessionManager.hasSignedInBefore { return true }
        if PayPreferences.isConfigured { return true }
        if CSSupAccess.hasAnswered { return true }
        if defaults.object(forKey: "workCity") != nil { return true }
        if let seen = defaults.object(forKey: "whatsNewSeenRevision") as? Int, seen > 6 {
            return true
        }
        if let tm = BarcodeStore.value, !tm.isEmpty, !DemoMode.isEnabled { return true }
        return false
    }
}

private enum AppTab: Hashable {
    case home, timeline, alerts, keys, settings
}

private struct MainTabView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @AppStorage("csSupKeysUnlocked") private var keysUnlocked = false
    @State private var selectedTab: AppTab = .home
    @State private var homeResetToken = 0
    @State private var showingLogin = false
    @State private var showingBreaks = false
    @State private var showingDiscountCard = false
    @State private var homeJump: HomeJump?
    @State private var monthCommand: MonthCommand?
    @State private var timelineRefreshTrigger = 0
    @State private var isSyncingTimeline = false
    @State private var alertsFilter: AlertsFilter = .unread
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private static let tabBarHeight: CGFloat = 49

    /// Frost + slight darken behind the tab bar only for the all-white Light
    /// calendar while iOS itself is in Light Mode. Hidden in Dark Mode so the
    /// glass tab bar sits on the dark agenda as-is.
    private var showsLightBottomScrim: Bool {
        colorScheme == .light && theme.displayStyle(for: .light) == .light
    }

    private var isAuthenticated: Bool { sessionManager.state == .authenticated }

    /// Only while a returning user's session might still be restorable and
    /// they aren't already signing in by hand. Probing must only run while the app
    /// is in the active foreground scene to avoid 0x8BADF00D watchdog hangs
    /// during background scene updates.
    private var shouldProbeForSession: Bool {
        scenePhase == .active
            && UIApplication.shared.applicationState != .background
            && !isAuthenticated
            && !DemoMode.isEnabled
            && SessionManager.hasSignedInBefore
            && !showingLogin
    }

    var body: some View {
        TabView(selection: selectionBinding) {
            Tab("Home", systemImage: "calendar", value: AppTab.home) {
                HomeCalendarView(resetToken: homeResetToken, onSignIn: {
                    showingLogin = true
                }, jump: homeJump, monthCommand: monthCommand)
            }
            Tab("Timeline", systemImage: "list.bullet", value: AppTab.timeline) {
                ScheduleListView(refreshTrigger: timelineRefreshTrigger, isSyncing: $isSyncingTimeline)
            }
            Tab("Alerts", systemImage: "bell.fill", value: AppTab.alerts) {
                AlertsView(isActive: selectedTab == .alerts, filter: $alertsFilter)
            }
            if keysUnlocked {
                Tab("Keys", systemImage: "key.fill", value: AppTab.keys) {
                    KeysView()
                }
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
            ZStack(alignment: .bottom) {
                if showsLightBottomScrim {
                    LightModeBottomScrim()
                        .frame(height: 168)
                        .ignoresSafeArea(edges: .bottom)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }

                shiftBar(for: selectedTab)
                    .padding(.bottom, Self.tabBarHeight)
            }
            .animation(.easeInOut(duration: 0.22), value: showsLightBottomScrim)
        }
        // Background-refresh the schedule when entering the foreground with an
        // active session, so it's fresh right away; gated on `isAuthenticated` so
        // this can't burn the auto-sync throttle window before login.
        .task {
            if isAuthenticated { try? await ScheduleSyncCoordinator.runSync() }
        }
        .onChange(of: sessionManager.state) { _, newState in
            guard newState == .authenticated else { return }
            showingLogin = false
            Task { try? await ScheduleSyncCoordinator.runSync(force: true) }
        }
        // When in Rainbow theme, morph the background gradient and accents into
        // a different combination of 3 colors on every tab change.
        .onChange(of: selectedTab) { _, _ in
            ThemeManager.shared.advanceRainbowCombo()
        }
        .onChange(of: colorScheme, initial: true) { _, newScheme in
            ThemeManager.shared.updateActiveColorScheme(newScheme)
        }
        .onChange(of: keysUnlocked) { _, unlocked in
            if !unlocked && selectedTab == .keys {
                selectedTab = .home
            }
        }
        // Breaks has no tab of its own: it opens from the countdown pill during a
        // shift, and from tapping a break widget or Live Activity.
        .sheet(isPresented: $showingBreaks) {
            BreaksView()
                .tint(theme.current.readableAccent)
                .presentationDragIndicator(.visible)
        }
        // Tapping the Lock Screen or Home Screen barcode widget opens the full-screen
        // official discount card directly with 100% boosted screen brightness.
        .sheet(isPresented: $showingDiscountCard) {
            if let id = BarcodeStore.value {
                DiscountCardModalView(tmID: id)
                    .presentationDragIndicator(.visible)
            }
        }
        .onOpenURL { url in
            if url.scheme == "wfschedule" {
                if url.host == "breaks" { showingBreaks = true }
                if url.host == "barcode" { showingDiscountCard = true }
            }
        }
        .sheet(isPresented: $showingLogin) {
            LoginView()
                .tint(theme.current.readableAccent)
                .presentationDragIndicator(.visible)
        }
        .background {
            if shouldProbeForSession { SessionRestoreProbe() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                sessionManager.handleAppDidEnterBackground()
            case .active:
                sessionManager.handleAppWillEnterForeground()
                if !isAuthenticated && !sessionManager.isRestoringSession && hasSeenWelcome {
                    Task { await sessionManager.attemptCookieRestore() }
                }
            default:
                break
            }
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
        case .keys, .settings:
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

/// Progressive frost and a light dim behind the tab bar so white agenda text
/// stays readable in the Light calendar. Only drawn while iOS Light Mode is on.
private struct LightModeBottomScrim: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.regularMaterial)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.45), location: 0.42),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.black.opacity(0.05), location: 0.38),
                    .init(color: Color.black.opacity(0.16), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
