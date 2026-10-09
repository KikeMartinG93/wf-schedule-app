import Foundation
import UserNotifications

/// Wraps UNUserNotificationCenter for the three notification types this app sends:
/// schedule-change alerts, 60-minute pre-shift reminders, and login-required alerts.
/// Reminders are scheduled with UNCalendarNotificationTrigger so iOS can deliver
/// them even if the app never runs again before the shift.
enum NotificationService {
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert])) ?? false
    }

    static func notifyChanges(_ changes: [ScheduleChangeKind]) {
        guard !changes.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Schedule updated")
        content.body = summarize(changes)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "schedule-change-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        let center = UNUserNotificationCenter.current()
        Task {
            // Schedule changes are the one notification worth interrupting for.
            // Critical Alerts (ignore silent mode and Do Not Disturb) need an
            // entitlement Apple grants on request; once it's added and the user
            // allows it, this upgrades on its own. Until then Time Sensitive
            // still breaks through Focus and the notification summary.
            let settings = await center.notificationSettings()
            if settings.criticalAlertSetting == .enabled {
                content.interruptionLevel = .critical
                content.sound = .defaultCritical
            } else {
                content.interruptionLevel = .timeSensitive
            }
            try? await center.add(request)
        }
    }

    /// Minimum gap between "Sign in required" alerts. Silent re-login can fail
    /// repeatedly across many background wakes in a row (e.g. UKG changed its
    /// login flow) — without this, that turns into a notification every time,
    /// which taught the user nothing new after the first one.
    private static let loginRequiredCooldown: TimeInterval = 6 * 60 * 60
    private static let lastLoginRequiredNotifiedKey = "lastLoginRequiredNotifiedAt"

    static func notifyLoginRequired() {
        let defaults = UserDefaults.standard
        if let last = defaults.object(forKey: lastLoginRequiredNotifiedKey) as? Date,
           Date().timeIntervalSince(last) < loginRequiredCooldown {
            return
        }
        defaults.set(Date(), forKey: lastLoginRequiredNotifiedKey)

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Sign in required")
        content.body = String(localized: "WF Schedule couldn't refresh your schedule automatically. Open the app to sign in again.")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "login-required",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Replaces all previously scheduled shift reminders with one 60-minute-before
    /// reminder per upcoming shift. Called after every successful sync so reminders
    /// stay accurate as shifts change.
    static func rescheduleShiftReminders(for shifts: [Shift]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let reminderIds = pending
                .filter { $0.identifier.hasPrefix("shift-reminder-") }
                .map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: reminderIds)

            let now = Date()
            for shift in shifts {
                let reminderTime = shift.startTime.addingTimeInterval(-60 * 60)
                guard reminderTime > now else { continue }

                let content = UNMutableNotificationContent()
                content.title = String(localized: "Shift starting soon")
                content.body = String(localized: "\(shift.job) starts at \(Self.timeFormatter.string(from: shift.startTime))")
                content.sound = .default

                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderTime)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "shift-reminder-\(shift.id)",
                    content: content,
                    trigger: trigger
                )
                center.add(request)
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private static func summarize(_ changes: [ScheduleChangeKind]) -> String {
        var newCount = 0, changedCount = 0, removedCount = 0
        for change in changes {
            switch change {
            case .new: newCount += 1
            case .changed: changedCount += 1
            case .removed: removedCount += 1
            }
        }
        var parts: [String] = []
        if newCount > 0 { parts.append(String(localized: "\(newCount) new")) }
        if changedCount > 0 { parts.append(String(localized: "\(changedCount) changed")) }
        if removedCount > 0 { parts.append(String(localized: "\(removedCount) removed")) }
        return String(localized: "Shifts: \(parts.joined(separator: ", "))")
    }
}
