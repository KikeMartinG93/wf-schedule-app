import WidgetKit
import SwiftUI

/// "Dynamic Approach": a Code 128 barcode encoding "491" + TM ID + "0", drawn as
/// a vector shape (see `Code128Shape` for why it isn't a bitmap). Core Image, and
/// so CICode128BarcodeGenerator, doesn't exist on watchOS, hence Code128Barcode.
struct DynamicBarcodeComplication: Widget {
    let kind: String = "DynamicBarcodeComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BarcodeTimelineProvider()) { entry in
            DynamicBarcodeComplicationView(entry: entry).fontDesign(.rounded)
        }
        .configurationDisplayName("Discount Barcode")
        .description("Your employee discount barcode, generated from your TM ID.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct DynamicBarcodeComplicationView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: BarcodeEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                rectangular
            case .accessoryCircular:
                if entry.barcode != nil {
                    Image(systemName: "barcode")
                        .font(.title2)
                }
            case .accessoryInline:
                if entry.barcode != nil {
                    Image(systemName: "barcode")
                }
            default:
                EmptyView()
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "wfschedule://barcode"))
    }

    @ViewBuilder
    private var rectangular: some View {
        if let tmID = entry.barcode?.trimmingCharacters(in: .whitespacesAndNewlines), !tmID.isEmpty,
           let modules = Code128Barcode.modules(for: tmID) {
            ZStack {
                // Only in full color: the black behind the holes is what makes
                // them read as black bars. In accented/vibrant modes an opaque
                // backing would be recolored into a solid block covering them.
                if renderingMode == .fullColor {
                    Color.black
                }
                Code128Shape(modules: modules)
                    .fill(Color.white, style: FillStyle(eoFill: true))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Text("Set TM ID in the phone app")
                .font(.caption2)
        }
    }
}
