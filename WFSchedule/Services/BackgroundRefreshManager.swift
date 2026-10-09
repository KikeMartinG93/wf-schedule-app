import Foundation
import BackgroundTasks

/// Registers and schedules the BGAppRefreshTask iOS uses to opportunistically
/// run a schedule sync while the app isn't in the foreground. iOS decides the
/// actual timing — this only requests the opportunity and re-requests one after
/// each run so refresh keeps happening as long as the system allows it.
enum BackgroundRefreshManager {
    static let taskIdentifier = "com.marting.WFM.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            handle(task: task as! BGAppRefreshTask)
        }
    }

    @MainActor
    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        // Earliest begin date is a hint, not a guarantee — iOS decides actual
        // timing and can skip an opportunity entirely. ScheduleSyncCoordinator's
        // own throttle is the real 2x/day cap (12h), so this asks for a wake at
        // half that (6h) — two chances per throttle window instead of one —
        // to make it more likely iOS actually grants one wake inside each 12h
        // window, without asking so often it burns battery on wakes that
        // immediately no-op against the throttle.
        var earliest = Date(timeIntervalSinceNow: 6 * 60 * 60)
        // During a shift, ask to be woken right after it ends: that's the only
        // chance to take the break Live Activity down without the app open.
        if let end = BreakActivityManager.activeShiftEnd(), end < earliest { earliest = end.addingTimeInterval(60) }
        request.earliestBeginDate = earliest
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(task: BGAppRefreshTask) {
        Task { @MainActor in scheduleNext() }
        // Also the periodic check-in that gets an overdue checklist task's
        // repeating reminder actually started while the app isn't running —
        // see ChecklistReminderService's doc comment for why this needs to
        // run from more than one place.
        ChecklistReminderService.refreshAllReminders()
        Task { @MainActor in BreakActivityManager.sync() }

        let syncTask = Task {
            do {
                try await ScheduleSyncCoordinator.runSync()
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            syncTask.cancel()
        }
    }
}
