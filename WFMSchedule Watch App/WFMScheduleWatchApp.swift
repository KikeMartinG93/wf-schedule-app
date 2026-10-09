import SwiftUI
import WidgetKit

@main
struct WFMScheduleWatchApp: App {
    // Activating here (not just in BarcodeWatchView.onAppear) means the
    // WatchConnectivity session comes up the moment the app process starts
    // for ANY reason — including watchOS launching it briefly in the
    // background to refresh a complication — rather than only when the user
    // manually opens the full-screen view. A complication alone was never
    // enough to trigger this, so a value pushed from the phone had nowhere
    // to land if you never opened the app itself.
    //
    // The complication's timeline uses policy `.never` (the barcode almost
    // never changes) and only gets explicitly reloaded when a new value
    // actually arrives over WatchConnectivity — so after installing a new
    // build of the extension itself, the OLD rendered snapshot can keep
    // showing (stretched to whatever the current cell shape is) until
    // watchOS gets around to its own refresh cycle on its own schedule,
    // rather than immediately. Forcing a reload here means every app launch
    // (including the brief background ones watchOS does to service a
    // complication) re-renders against the current code right away instead
    // of waiting on that.
    init() {
        WatchBarcodeReceiver.shared.activate()
        WidgetCenter.shared.reloadAllTimelines()
    }

    var body: some Scene {
        WindowGroup {
            // Opens on the shift countdown; scroll up/down (Digital Crown) for the barcode.
            TabView {
                WatchShiftView()
                BarcodeWatchView()
            }
            .tabViewStyle(.verticalPage)
        }
    }
}
