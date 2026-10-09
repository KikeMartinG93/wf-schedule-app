import ActivityKit
import Foundation
@preconcurrency import UserNotifications

/// Decides when the break Live Activity should exist: only while a shift is on.
/// Each shift gets its own `BreakFlow` (see `BreakRhythm`); this starts the
/// activity for it, and ends it when the shift is over or the feature is off.
///
/// iOS only lets an app START a Live Activity while it's in the foreground, so a
/// shift's activity appears the first time the app is opened once the shift has
/// begun. A "shift started" notification is scheduled for exactly that moment to
/// make it a single tap. From there the Lock Screen buttons and the alarm run
/// without the app being open.
@MainActor
enum BreakActivityManager {
    static let enabledKey = BreakFlowEngine.enabledKey

    static var isEnabled: Bool { BreakFlowEngine.isEnabled }

    private static let startNoticePrefix = "break-start-"

    /// The shift being worked right now, if any.
    private static func activeShift(at now: Date) -> Shift? {
        #if DEBUG
        // Testing hook: `defaults write <bundle id> debugShiftStart <unix time>`
        // pretends an eight hour shift began then.
        if let start = UserDefaults.standard.object(forKey: "debugShiftStart") as? Double {
            let begin = Date(timeIntervalSince1970: start)
            let end = begin.addingTimeInterval(8 * 3600)
            guard begin <= now && now < end else { return nil }
            return Shift(ukgRecordId: nil, date: Calendar.current.startOfDay(for: begin), startTime: begin,
                         endTime: end, job: "Debug", location: nil, kind: .regular, payCode: nil, notes: nil)
        }
        #endif
        return ScheduleStore.shared.load()?.shifts.first { $0.startTime <= now && now < $0.endTime }
    }

    /// When the current shift ends — for scheduling a background wake to clear the
    /// activity, since nothing else runs at that moment.
    static func activeShiftEnd(at now: Date = Date()) -> Date? {
        isEnabled ? activeShift(at: now)?.endTime : nil
    }

    /// Runs whenever the app comes forward, after a schedule sync, when the
    /// Settings switch changes, and on a background wake.
    static func sync(now: Date = Date()) {
        Task { await syncNow(now) }
    }

    static func syncNow(_ now: Date = Date()) async {
        scheduleStartNotices(now: now)

        guard isEnabled, let shift = activeShift(at: now) else {
            await BreakFlowEngine.tearDown()
            return
        }

        let fresh = BreakFlow.make(shiftStart: shift.startTime, shiftEnd: shift.endTime)
        if var flow = BreakFlowStore.load(), flow.shiftID == fresh.shiftID {
            // Same shift: keep what's been started, but follow an edited end time.
            if flow.shiftEnd != fresh.shiftEnd || flow.breaks != fresh.breaks {
                flow.shiftEnd = fresh.shiftEnd
                flow.breaks = fresh.breaks
                flow.runs = flow.runs.filter { fresh.breaks.indices.contains($0.key) }
                BreakFlowStore.save(flow)
            }
        } else {
            // A different shift than the one stored: clear the old one's alarms first.
            await BreakFlowEngine.tearDown()
            BreakFlowStore.save(fresh)
        }
        await BreakFlowEngine.refresh(canRequest: true)
        await BreakFlowEngine.requestAlarmAuthorizationIfNeeded()
    }

    // MARK: - Shift-start notice

    private static func scheduleStartNotices(now: Date) {
        let upcoming: [Shift] = isEnabled
            ? Array((ScheduleStore.shared.load()?.shifts ?? [])
                .filter { $0.startTime > now && $0.endTime.timeIntervalSince($0.startTime) > 15 * 60 }
                .sorted { $0.startTime < $1.startTime }
                .prefix(14))
            : []

        let prefix = startNoticePrefix
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.getPendingNotificationRequests { [notificationCenter] pending in
            let stale = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            notificationCenter.removePendingNotificationRequests(withIdentifiers: stale)
            for shift in upcoming {
                let content = UNMutableNotificationContent()
                content.title = String(localized: "Shift started")
                content.body = String(localized: "Tap to start your break timers.")
                content.sound = .default
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: shift.startTime)
                notificationCenter.add(UNNotificationRequest(
                    identifier: "\(prefix)\(shift.id)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                ))
            }
        }
    }
}
