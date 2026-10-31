import WidgetKit
import SwiftUI

@main
struct NextShiftWidgetBundle: WidgetBundle {
    var body: some Widget {
        CalendarAgendaWidget()
        MonthGridAgendaWidget()
        NextShiftWidget()
        BarcodeWidget()
        BreakWidget()
        BreakLiveActivity()
    }
}
