import WidgetKit
import SwiftUI

struct BreakWidget: Widget {
    let kind = "BreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BreakProvider()) { entry in
            BreakWidgetView(entry: entry)
                .fontDesign(FontPreference.design)
                .widgetURL(URL(string: "wfschedule://breaks"))
        }
        .configurationDisplayName("Break Timer")
        .description("Time until your next break, or how long it's overdue.")
        .supportedFamilies([.accessoryRectangular, .systemSmall])
    }
}
