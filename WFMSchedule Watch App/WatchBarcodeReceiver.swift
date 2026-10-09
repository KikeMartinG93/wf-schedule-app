import Foundation
import WatchConnectivity
import WidgetKit

/// Receives the barcode number pushed from `BarcodePhoneSync` on the iPhone
/// side, writes it into the App-Group-shared store, and asks WidgetKit to
/// redraw the complication immediately rather than waiting for its own
/// timeline schedule.
@MainActor
final class WatchBarcodeReceiver: NSObject, ObservableObject {
    static let shared = WatchBarcodeReceiver()

    @Published private(set) var barcode: String? = WatchBarcodeStore.value
    @Published private(set) var shifts: [WatchShift] = WatchShifts.decode(
        UserDefaults(suiteName: WatchBarcodeStore.appGroupID)?.string(forKey: WatchBarcodeReceiver.shiftsKey))
    @Published private(set) var highContrast = ContrastPreference.high
    @Published private(set) var roundedFont = FontPreference.rounded

    private static let shiftsKey = "watchShiftsJSON"

    private override init() {
        super.init()
        #if DEBUG
        // Screenshot/testing aid: launch with SIMCTL_CHILD_WF_DEMO=onshift|next to skip pairing.
        let now = Date()
        switch ProcessInfo.processInfo.environment["WF_DEMO"] {
        case "onshift": shifts = [WatchShift(start: now.addingTimeInterval(-3 * 3600), end: now.addingTimeInterval(5 * 3600), job: "Demo")]
        case "next": shifts = [WatchShift(start: now.addingTimeInterval(2.5 * 3600), end: now.addingTimeInterval(10 * 3600), job: "Demo")]
        default: break
        }
        #endif
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    fileprivate func handle(applicationContext: [String: Any]) {
        let received = applicationContext["barcode"] as? String
        let normalized = (received?.isEmpty == false) ? received : nil
        WatchBarcodeStore.value = normalized
        barcode = normalized
        // The break plan rides along in the same context; the complication reads
        // it from the same shared defaults (see BreakStore).
        if let breaks = applicationContext["breaks"] as? String {
            UserDefaults(suiteName: WatchBarcodeStore.appGroupID)?
                .set(breaks.isEmpty ? nil : breaks, forKey: "breakPlanJSON")
        }
        // The schedule and the look (high contrast, font) follow the phone.
        if let json = applicationContext["shifts"] as? String {
            UserDefaults(suiteName: WatchBarcodeStore.appGroupID)?.set(json, forKey: Self.shiftsKey)
            shifts = WatchShifts.decode(json)
        }
        if let high = applicationContext["highContrast"] as? Bool {
            FontPreference.store.set(high, forKey: ContrastPreference.key)
            highContrast = high
        }
        if let rounded = applicationContext["roundedFont"] as? Bool {
            FontPreference.store.set(rounded, forKey: FontPreference.key)
            roundedFont = rounded
        }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension WatchBarcodeReceiver: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            self.handle(applicationContext: applicationContext)
        }
    }
}
