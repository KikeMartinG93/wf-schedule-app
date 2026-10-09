import WidgetKit
import SwiftUI

@main
struct NextShiftWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextShiftWidget()
        BarcodeWidget()
        BreakWidget()
        BreakLiveActivity()
    }
}
