import SwiftUI

@main
struct WFScheduleApp: App {
    @StateObject private var sessionManager = SessionManager.shared
    @AppStorage(AppLanguage.storageKey) private var languageCode: String = AppLanguage.system.rawValue

    init() {
        BackgroundRefreshManager.register()
    }

    private var activeLocale: Locale {
        let choice = AppLanguage(rawValue: languageCode) ?? .system
        return choice == .system ? .autoupdatingCurrent : Locale(identifier: choice.rawValue)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sessionManager)
                .environment(\.locale, activeLocale)
                .id(languageCode)
                .task {
                    // Bootstrap runs once per app launch (only if welcome was seen).
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
        if let shifts = ScheduleStore.shared.load()?.shifts {
            try? calendarSync.reconcileTitles(for: shifts)
        }

        _ = await NotificationService.requestAuthorization()
        BackgroundRefreshManager.scheduleNext()
        ChecklistReminderService.refreshAllReminders()
        BarcodePhoneSync.shared.activate()
        ScheduleStore.shared.republishExistingSnapshot()
        if let tmID = BarcodeStore.value { BarcodeStore.value = tmID }
    }
}
