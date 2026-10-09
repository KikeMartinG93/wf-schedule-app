import Foundation
import WatchConnectivity

/// Pushes the discount barcode number to the paired Watch app whenever it
/// changes. This is the one narrow, deliberate reintroduction of
/// WatchConnectivity after removing the earlier (much larger) two-way
/// schedule-sync bridge — a single small string, one direction, sent via
/// `updateApplicationContext` (delivered the next time the Watch app is
/// reachable even if it wasn't running when this was called, and always
/// reflects only the latest value rather than queuing up history, which is
/// exactly the "current settings value" semantics this needs).
@MainActor
final class BarcodePhoneSync: NSObject, WCSessionDelegate {
    static let shared = BarcodePhoneSync()

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        // The watch's countdown needs the schedule, so a new sync goes over too.
        NotificationCenter.default.addObserver(forName: ScheduleStore.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.send(BarcodeStore.value) }
        }
    }

    /// Upcoming (and in-progress) shifts for the watch: ending within the last
    /// few hours through the next two weeks, time off excluded.
    private func upcomingShifts() -> [WatchShift] {
        let now = Date()
        let from = now.addingTimeInterval(-6 * 3600)
        let to = now.addingTimeInterval(14 * 86_400)
        return (ScheduleStore.shared.load()?.shifts ?? [])
            .filter { $0.kind != .timeOff && $0.endTime > from && $0.startTime < to }
            .sorted { $0.startTime < $1.startTime }
            .prefix(40)
            .map { WatchShift(start: $0.startTime, end: $0.endTime, job: $0.job) }
    }

    func send(_ barcode: String?) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        // The timestamp makes every send a "changed" context. WatchConnectivity
        // drops an application context identical to the previous one, so without
        // it a watch that lost its stored copy (e.g. after a reinstall) would
        // never get the number again until it was edited.
        try? WCSession.default.updateApplicationContext([
            "barcode": barcode ?? "",
            "breaks": BreakStore.rawJSON ?? "",
            "shifts": WatchShifts.encode(upcomingShifts()),
            "highContrast": ContrastPreference.high,
            "roundedFont": FontPreference.rounded,
            "sentAt": Date().timeIntervalSince1970,
        ])
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in
            self.send(BarcodeStore.value)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
