import WidgetKit
import SwiftUI

/// Discount barcode widget: home screen medium plus a Lock Screen rectangle,
/// both drawn from the TM ID saved in the app's Settings as the official
/// Whole Foods Market UPC-A electronic discount card.
struct BarcodeWidgetEntry: TimelineEntry {
    let date: Date
    let tmID: String?
}

struct BarcodeWidgetProvider: TimelineProvider {
    private static var savedTMID: String? { SecureTMID.value }

    func placeholder(in context: Context) -> BarcodeWidgetEntry {
        BarcodeWidgetEntry(date: Date(), tmID: "1234567")
    }

    func getSnapshot(in context: Context, completion: @escaping (BarcodeWidgetEntry) -> Void) {
        completion(BarcodeWidgetEntry(date: Date(), tmID: Self.savedTMID ?? (context.isPreview ? "1234567" : nil)))
    }

    /// The app reloads timelines whenever the TM ID is edited, so one
    /// never-expiring entry is enough.
    func getTimeline(in context: Context, completion: @escaping (Timeline<BarcodeWidgetEntry>) -> Void) {
        completion(Timeline(entries: [BarcodeWidgetEntry(date: Date(), tmID: Self.savedTMID)], policy: .never))
    }
}

struct BarcodeWidget: Widget {
    let kind = "BarcodeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BarcodeWidgetProvider()) { entry in
            BarcodeWidgetView(entry: entry).fontDesign(FontPreference.design)
        }
        .configurationDisplayName("Discount Barcode")
        .description("Your employee discount barcode, generated from your TM ID.")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}

struct BarcodeWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: BarcodeWidgetEntry
    /// Lets the in-app showcase draw a specific size (the environment value is read-only).
    var familyOverride: WidgetFamily? = nil

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    private var isAccessory: Bool { family == .accessoryRectangular }

    private var tmID: String? {
        guard let value = entry.tmID?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    var body: some View {
        Group {
            if let tmID, let upcModules = UPCABarcode.modules(for: tmID) {
                if isAccessory {
                    accessoryBars(tmID: tmID, modules: upcModules)
                } else {
                    UPCABarcodeCard(input: tmID)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Text("Set your TM ID in the app's Settings")
                    .font(isAccessory ? .caption2 : .subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isAccessory ? Color.primary : Color.secondary)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "wfschedule://barcode"))
    }

    /// Lock Screen version: in full color, renders the exact UPC-A discount card
    /// with guard bars and masked digits; in tinted/vibrant mode, uses UPCAShape
    /// with extended guard bars. Tapping always opens the full-screen card.
    @ViewBuilder
    private func accessoryBars(tmID: String, modules: [UPCABarcode.Module]) -> some View {
        if renderingMode == .fullColor {
            UPCABarcodeCard(input: tmID)
                .padding(3)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                UPCAShape(modules: modules)
                    .fill(Color.white, style: FillStyle(eoFill: true))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}
