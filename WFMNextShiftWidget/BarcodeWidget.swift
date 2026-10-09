import WidgetKit
import SwiftUI

/// Discount barcode widget: home screen medium plus a Lock Screen rectangle,
/// both drawn from the TM ID saved in the app's Settings as a
/// Code 128 barcode of "491" + TM ID + "0".
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
            if let tmID, let modules = Code128Barcode.modules(for: tmID) {
                if isAccessory {
                    bars(modules)
                } else {
                    VStack(spacing: 8) {
                        ZStack {
                            Color.white
                            Code128BarsShape(modules: modules)
                                .fill(Color.black)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 6)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        Text(verbatim: SecureTMID.masked)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Set your TM ID in the app's Settings")
                    .font(isAccessory ? .caption2 : .subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isAccessory ? Color.primary : Color.secondary)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    /// Lock Screen version: bars as holes in a solid block (see `Code128Shape`)
    /// so they survive the Lock Screen's tinted rendering; black backing only in
    /// full color. The Home Screen widget is transparent instead and draws the
    /// bars in black on a white card for high scanner contrast.
    private func bars(_ modules: [Bool]) -> some View {
        ZStack {
            if renderingMode == .fullColor {
                Color.black
            }
            Code128Shape(modules: modules)
                .fill(Color.white, style: FillStyle(eoFill: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
