import ActivityKit
import AlarmKit
import AppIntents
import Foundation
import SwiftUI
import UserNotifications

/// Stored in the shared app-group defaults, next to the older `BreakStore`.
enum BreakFlowStore {
    private static let key = "breakFlowJSON"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: BreakStore.appGroupID) }

    static func load() -> BreakFlow? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(BreakFlow.self, from: data)
    }

    static func save(_ flow: BreakFlow?) {
        if let flow, let data = try? JSONEncoder().encode(flow) {
            defaults?.set(data, forKey: key)
        } else {
            defaults?.removeObject(forKey: key)
        }
    }
}

struct BreakAlarmMetadata: AlarmMetadata {}

/// Runs the Lock Screen break buttons: starts a timer with an alarm at its end,
/// and keeps the Live Activity in step. Everything here is reachable from the
/// buttons themselves, which run in the app's process even when the app isn't open.
@MainActor
enum BreakFlowEngine {
    static let enabledKey = "breakLiveActivityEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// `end` is asynchronous, so an activity that's on its way out can still be
    /// listed for a moment. Remembering those IDs stops a quick end-then-start
    /// from updating the dying activity instead of starting a new one.
    private static var endingIDs = Set<String>()

    private static var live: [Activity<BreakActivityAttributes>] {
        Activity<BreakActivityAttributes>.activities.filter {
            !endingIDs.contains($0.id) && ($0.activityState == .active || $0.activityState == .stale)
        }
    }

    // MARK: - Live Activity

    /// Puts the Live Activity in line with the stored flow. Starting one needs
    /// the app in the foreground, so `canRequest` is only true from there; from a
    /// button it can only update the one that's already on screen.
    static func refresh(now: Date = Date(), canRequest: Bool) async {
        let existing = live
        guard isEnabled, ActivityAuthorizationInfo().areActivitiesEnabled,
              let flow = BreakFlowStore.load(), let state = flow.contentState(at: now) else {
            await end(existing)
            return
        }

        // An activity that starts out already stale isn't shown, so a prompt whose
        // time has come gets no stale date; the view works out "ready" from `at`.
        let content = ActivityContent(state: state, staleDate: state.at > now ? state.at : nil)

        if let current = existing.first {
            await current.update(content)
            await end(Array(existing.dropFirst()))
        } else if canRequest {
            _ = try? Activity.request(attributes: BreakActivityAttributes(), content: content)
        }
    }

    static func end(_ activities: [Activity<BreakActivityAttributes>]) async {
        for activity in activities {
            endingIDs.insert(activity.id)
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// No shift, or the feature is off: nothing should be running, ringing or waiting.
    static func tearDown() async {
        if let flow = BreakFlowStore.load() {
            for run in flow.runs.values { cancelAlarm(run.alarmID) }
        }
        BreakFlowStore.save(nil)
        await end(live)
    }

    // MARK: - Buttons

    static func startBreak(stage: Int, now: Date = Date()) async {
        guard var flow = BreakFlowStore.load(), now < flow.shiftEnd else {
            await refresh(now: now, canRequest: false)
            return
        }
        let alarmID = UUID()
        guard flow.start(stage: stage, at: now, alarmID: alarmID), let run = flow.runs[stage] else {
            await refresh(now: now, canRequest: false)
            return
        }
        BreakFlowStore.save(flow)
        await scheduleAlarm(id: alarmID, at: run.endsAt, kind: flow.breaks[stage].kind, stage: stage, now: now)
        await refresh(now: now, canRequest: false)
    }

    /// The alarm's Stop button. The timer is done either way; this just makes the
    /// Live Activity move on (or end, if that was the last break) right away.
    static func finishBreak(stage: Int, now: Date = Date()) async {
        guard var flow = BreakFlowStore.load() else { return }
        flow.finish(stage: stage)
        BreakFlowStore.save(flow)
        await refresh(now: now, canRequest: false)
    }

    // MARK: - Alarm

    /// Asked for while the app is open (when a shift's breaks start), not from
    /// inside a Lock Screen tap, where a permission prompt has nowhere good to appear.
    static func requestAlarmAuthorizationIfNeeded() async {
        guard AlarmManager.shared.authorizationState == .notDetermined else { return }
        _ = try? await AlarmManager.shared.requestAuthorization()
    }

    /// A real alarm (rings through Silent and Focus) when the user has allowed
    /// alarms; otherwise a time-sensitive notification, which at least shows up.
    private static func scheduleAlarm(id: UUID, at endsAt: Date, kind: BreakKind, stage: Int, now: Date) async {
        let manager = AlarmManager.shared
        var authorization = manager.authorizationState
        if authorization == .notDetermined {
            authorization = (try? await manager.requestAuthorization()) ?? .denied
        }
        guard authorization == .authorized else {
            await scheduleNotification(id: id, at: endsAt, kind: kind, now: now)
            return
        }

        let title: LocalizedStringResource = kind == .lunch ? "Lunch is over" : "Break is over"
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title)
        } else {
            alert = AlarmPresentation.Alert(
                title: title,
                stopButton: AlarmButton(text: "Done", textColor: .white, systemImageName: "checkmark")
            )
        }
        let attributes = AlarmAttributes<BreakAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: .green
        )
        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(endsAt),
            attributes: attributes,
            stopIntent: FinishBreakIntent(stage: stage)
        )
        do {
            _ = try await manager.schedule(id: id, configuration: configuration)
        } catch {
            await scheduleNotification(id: id, at: endsAt, kind: kind, now: now)
        }
    }

    private static func cancelAlarm(_ id: UUID?) {
        guard let id else { return }
        try? AlarmManager.shared.cancel(id: id)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["break-end-\(id)"])
    }

    private static func scheduleNotification(id: UUID, at endsAt: Date, kind: BreakKind, now: Date) async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: kind == .lunch ? "Lunch is over" : "Break is over")
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, endsAt.timeIntervalSince(now)), repeats: false)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "break-end-\(id)", content: content, trigger: trigger)
        )
    }
}
