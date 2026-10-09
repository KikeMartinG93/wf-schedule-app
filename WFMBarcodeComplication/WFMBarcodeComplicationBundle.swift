import WidgetKit
import SwiftUI

@main
struct WFMBarcodeComplicationBundle: WidgetBundle {
    var body: some Widget {
        DynamicBarcodeComplication()
        BreakComplication()
    }
}
