import Foundation
import WidgetKit

/// A built-in demonstration mode: the whole app runs on a made-up schedule and
/// change history, with no UKG account and no network. Nothing real is read or
/// overwritten — the stores hand out this sample data while it's on, and go back
/// to the real data the moment it's turned off.
enum DemoMode {
    static let storageKey = "demoModeEnabled"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: storageKey) }

    /// Sample alerts; kept in memory so "mark as viewed" and notes work in the demo.
    static var entries: [ChangeLogEntry] = []

    static func set(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: storageKey)
        entries = enabled ? makeEntries() : []
        ScheduleStore.shared.republishExistingSnapshot()
        ShiftIndexer.reindex()
        NotificationCenter.default.post(name: ScheduleStore.didChangeNotification, object: nil)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Sample schedule

    /// A rolling schedule around today: two weeks back, five weeks ahead, mixing
    /// Supervisor and Cash Office shifts (with an active shift today to showcase
    /// the countdown and break tools).
    static func snapshot(now: Date = Date()) -> ScheduleSnapshot {
        ScheduleSnapshot(fetchedAt: now, shifts: makeShifts(now: now), pendingRemovalMisses: [:])
    }

    private static func makeShifts(now: Date) -> [Shift] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        // Ensure today always has an active shift running so the countdown pill,
        // break tools, and shift details are immediately interactive.
        let todayStart = now.addingTimeInterval(-2 * 3600)
        let todayEnd = now.addingTimeInterval(5.5 * 3600)
        let todayShift = Shift(
            ukgRecordId: nil,
            date: today,
            startTime: todayStart,
            endTime: todayEnd,
            job: "Supervisor",
            location: "Demo Store",
            kind: .regular,
            payCode: nil,
            notes: "Cash Office audit scheduled. Bring departmental safe keys."
        )

        // weekday: 1 = Sunday … 7 = Saturday
        let pattern: [Int: (job: String, start: (Int, Int), end: (Int, Int))] = [
            1: ("Store Support", (10, 0), (18, 30)),
            2: ("Supervisor", (7, 45), (15, 45)),
            3: ("Supervisor", (7, 0), (15, 0)),
            4: ("Customer Service", (8, 0), (16, 30)),
            5: ("Cash Office", (11, 30), (19, 30)),
            6: ("Cash Office", (11, 30), (19, 30)),
            7: ("Supervisor", (6, 0), (14, 30)),
        ]

        var shifts: [Shift] = [todayShift]
        for offset in -14...35 {
            if offset == 0 { continue }
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let plan = pattern[calendar.component(.weekday, from: day)],
                  let start = calendar.date(bySettingHour: plan.start.0, minute: plan.start.1, second: 0, of: day),
                  let end = calendar.date(bySettingHour: plan.end.0, minute: plan.end.1, second: 0, of: day)
            else { continue }

            var shiftNotes: String? = nil
            var payCode: String? = nil
            var kind: ShiftKind = .regular

            if offset == 2 {
                shiftNotes = "Mid-day register audit at 2 PM."
            } else if offset == 5 {
                payCode = "Holiday Pay"
                shiftNotes = "Holiday premium rate applies."
            } else if offset == 8 {
                kind = .timeOff
                payCode = "Paid Time Off"
            }

            shifts.append(Shift(
                ukgRecordId: nil,
                date: day,
                startTime: start,
                endTime: end,
                job: plan.job,
                location: "Demo Store",
                kind: kind,
                payCode: payCode,
                notes: shiftNotes
            ))
        }
        return shifts.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Sample alerts

    private static func makeEntries() -> [ChangeLogEntry] {
        let now = Date()
        let upcoming = makeShifts(now: now).filter { $0.startTime > now }
        guard upcoming.count >= 4 else { return [] }

        let added = upcoming[3]
        let changed = upcoming[1]
        var before = changed
        before.startTime = changed.startTime.addingTimeInterval(-3600)
        before.endTime = changed.endTime.addingTimeInterval(-3600)
        let removed = upcoming[2]

        return [
            ChangeLogEntry(timestamp: now.addingTimeInterval(-2 * 3600), kind: .new, shift: added),
            ChangeLogEntry(timestamp: now.addingTimeInterval(-26 * 3600), kind: .changed, shift: changed, previousShift: before),
            ChangeLogEntry(timestamp: now.addingTimeInterval(-3 * 86400), kind: .removed, shift: removed,
                           swapNote: "Swapped with Alex", seen: true),
        ]
    }
}
