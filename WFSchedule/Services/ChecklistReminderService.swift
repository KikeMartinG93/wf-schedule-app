import Foundation
import UserNotifications

/// Implements "notify every 10 minutes until completed" for overdue checklist
/// tasks. iOS has no API for "repeat until some condition becomes true" — the
/// two building blocks available are a one-shot trigger and a fixed-interval
/// repeating trigger, so this schedules a `repeats: true` 10-minute-interval
/// notification per overdue task (one pending-notification slot each, well
/// under iOS's 64-per-app cap even alongside shift reminders) and cancels it
/// the instant the task is checked off.
///
/// Trade-off worth knowing: the repeating trigger only starts once this code
/// actually runs and notices the task is overdue — there's no way to pre-arm
/// it to start exactly at the due time while the app is backgrounded. So the
/// very first nag can lag behind the due time by however long it's been since
/// this last ran. To keep that window small, `refreshAllReminders()` is called
/// from every place the app has a chance to run: on launch/foreground, when
/// the Checklist tab appears, right after a task is toggled, and from the
/// existing background refresh task. Once scheduled, the repeat itself is
/// handled entirely by iOS and needs no further app wake-ups.
enum ChecklistReminderService {
    private static func identifier(for taskID: UUID) -> String {
        "checklist-\(taskID.uuidString)"
    }

    /// Checklist is switched off for now (its tab is hidden). While false,
    /// refreshAllReminders only cancels any checklist reminders left pending
    /// from earlier builds and schedules nothing new.
    static let isEnabled = false

    static func refreshAllReminders() {
        guard isEnabled else {
            let center = UNUserNotificationCenter.current()
            center.getPendingNotificationRequests { pending in
                let ids = pending.map(\.identifier).filter { $0.hasPrefix("checklist-") }
                if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }
            }
            return
        }
        let tasks = ChecklistStore.shared.loadTasks()
        let state = ChecklistStore.shared.loadState()
        let now = Date()
        let center = UNUserNotificationCenter.current()

        center.getPendingNotificationRequests { pending in
            let alreadyScheduled = Set(pending.map(\.identifier))

            for task in tasks {
                let id = identifier(for: task.id)
                let isDone = state.completedTaskIDs.contains(task.id)

                if isDone {
                    if alreadyScheduled.contains(id) {
                        center.removePendingNotificationRequests(withIdentifiers: [id])
                    }
                    continue
                }

                guard now >= task.dueTimeToday, !alreadyScheduled.contains(id) else { continue }

                let content = UNMutableNotificationContent()
                content.title = "\(task.category.rawValue) checklist"
                content.body = "\"\(task.title)\" was due at \(task.dueTimeString) — still not checked off."
                content.sound = .default

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10 * 60, repeats: true)
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                center.add(request)
            }
        }
    }

    static func cancelReminder(taskID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(for: taskID)])
    }

    /// Call right after flipping a task's completion — cancels immediately if
    /// now done, or re-evaluates right away if un-done (in case it's already
    /// overdue and needs its nag chain restarted).
    static func handleToggled(taskID: UUID, isCompleted: Bool) {
        if isCompleted {
            cancelReminder(taskID: taskID)
        } else {
            refreshAllReminders()
        }
    }
}
