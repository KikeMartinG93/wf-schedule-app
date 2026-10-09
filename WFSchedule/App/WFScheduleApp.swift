import SwiftUI

@main
struct WFScheduleApp: App {
    @StateObject private var sessionManager = SessionManager.shared
    @AppStorage(AppLanguage.storageKey) private var language: String = AppLanguage.system.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(FontPreference.key, store: FontPreference.store) private var roundedFont = true
    @ObservedObject private var theme = ThemeManager.shared

    init() {
        BackgroundRefreshManager.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .fontDesign(roundedFont ? .rounded : .default)
                .background(HighContrastApplier(enabled: theme.highContrast))
                .environmentObject(sessionManager)
                .environment(\.locale, (AppLanguage(rawValue: language) ?? .system).locale)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { BreakActivityManager.sync() }
                }
                .task {
                    BreakActivityManager.sync()
                    // On the very first launch the welcome sheet is showing, and
                    // system permission prompts on top of it are a bad first
                    // impression — RootView runs the same setup when it's dismissed.
                    if UserDefaults.standard.bool(forKey: "hasSeenWelcome") {
                        await AppBootstrap.run()
                    }
                }
        }
    }
}

/// Launch-time permission requests and background setup.
@MainActor
enum AppBootstrap {
    static func run() async {
        // Calendar access is requested FIRST, before anything else
        // in this task — it used to run after the notification
        // permission prompt, and since that call `await`s until
        // the user actually responds to that system dialog, the
        // calendar prompt could end up visibly delayed behind it
        // (or behind however long the user takes to notice/dismiss
        // it), which read as "it doesn't ask until I go to List" —
        // that tab's own sync happening to trigger the same
        // request again made it look tab-triggered. Doing it first
        // and independent of the UKG schedule sync (cleaning up
        // duplicate calendar events has nothing to do with the
        // network fetch) means this is unambiguously the first
        // thing the app does on every launch.
        let calendarSync = CalendarSyncService()
        try? await calendarSync.requestAccess()
        try? calendarSync.deduplicateEvents()

        _ = await NotificationService.requestAuthorization()
        BackgroundRefreshManager.scheduleNext()
        ChecklistReminderService.refreshAllReminders()
        BarcodePhoneSync.shared.activate()
        ScheduleStore.shared.republishExistingSnapshot()
        if let tmID = BarcodeStore.value { BarcodeStore.value = tmID }
    }
}
