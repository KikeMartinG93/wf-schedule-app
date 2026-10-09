import WidgetKit

struct BarcodeEntry: TimelineEntry {
    let date: Date
    let barcode: String?
}

struct BarcodeTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> BarcodeEntry {
        BarcodeEntry(date: Date(), barcode: "0123456789")
    }

    func getSnapshot(in context: Context, completion: @escaping (BarcodeEntry) -> Void) {
        completion(BarcodeEntry(date: Date(), barcode: WatchBarcodeStore.value))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BarcodeEntry>) -> Void) {
        let entry = BarcodeEntry(date: Date(), barcode: WatchBarcodeStore.value)
        // The barcode number essentially never changes on its own, so one
        // never-expiring entry is enough — `WatchBarcodeReceiver` actively
        // calls `WidgetCenter.reloadAllTimelines()` on the rare occasion a
        // new value actually arrives from the phone, rather than this
        // polling on a schedule.
        completion(Timeline(entries: [entry], policy: .never))
    }
}
