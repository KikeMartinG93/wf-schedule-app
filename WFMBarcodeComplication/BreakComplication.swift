import WidgetKit
import SwiftUI

struct BreakComplication: Widget {
    let kind = "BreakComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BreakProvider()) { entry in
            BreakWidgetView(entry: entry).fontDesign(.rounded)
        }
        .configurationDisplayName("Break Timer")
        .description("Time until your next break, or how long it's overdue.")
        .supportedFamilies([.accessoryRectangular])
    }
}
