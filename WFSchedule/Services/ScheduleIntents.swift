import AppIntents
import SwiftUI

enum DayChoice: String, AppEnum {
    case today, tomorrow

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Day"
    static let caseDisplayRepresentations: [DayChoice: DisplayRepresentation] = [
        .today: "Today",
        .tomorrow: "Tomorrow",
    ]

    var date: Date {
        let start = Calendar.current.startOfDay(for: Date())
        return self == .today ? start : (Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start)
    }
}

private func timeRange(_ shift: Shift) -> String {
    "\(shift.startTime.formatted(date: .omitted, time: .shortened))–\(shift.endTime.formatted(date: .omitted, time: .shortened))"
}

struct NextShiftIntent: AppIntent {
    static let title: LocalizedStringResource = "Next Shift"
    static let description = IntentDescription("Find out when your next shift starts.")

    func perform() async throws -> some IntentResult & ReturnsValue<ShiftEntity?> & ProvidesDialog & ShowsSnippetView {
        guard let shift = ShiftLibrary.nextShift() else {
            return .result(value: nil, dialog: "You have no upcoming shifts.", view: ShiftSnippet(shift: nil))
        }
        let when = shift.startTime.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
        return .result(
            value: ShiftEntity(shift),
            dialog: "Your next shift is \(shift.job) on \(when).",
            view: ShiftSnippet(shift: shift)
        )
    }
}

struct ScheduleForDayIntent: AppIntent {
    static let title: LocalizedStringResource = "Schedule for a Day"
    static let description = IntentDescription("See what shifts you have today or tomorrow.")

    @Parameter(title: "Day", default: .today)
    var day: DayChoice

    static var parameterSummary: some ParameterSummary {
        Summary("Schedule for \(\.$day)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[ShiftEntity]> & ProvidesDialog {
        let shifts = ShiftLibrary.shifts(on: day.date)
        let entities = shifts.map(ShiftEntity.init)

        guard !shifts.isEmpty else {
            switch day {
            case .today: return .result(value: entities, dialog: "You are not working today.")
            case .tomorrow: return .result(value: entities, dialog: "You are not working tomorrow.")
            }
        }

        let summary = shifts.map { "\($0.job) \(timeRange($0))" }.formatted(.list(type: .and))
        switch day {
        case .today: return .result(value: entities, dialog: "Today you work \(summary).")
        case .tomorrow: return .result(value: entities, dialog: "Tomorrow you work \(summary).")
        }
    }
}

struct ShiftSnippet: View {
    let shift: Shift?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Next Shift")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let shift {
                Text(verbatim: shift.job)
                    .font(.headline)
                Text("\(shift.startTime.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) · \(timeRange(shift))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("You have no upcoming shifts.")
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

struct WFScheduleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextShiftIntent(),
            phrases: [
                "What is my next shift in \(.applicationName)",
                "When do I work next in \(.applicationName)",
                "Next shift in \(.applicationName)",
            ],
            shortTitle: "Next Shift",
            systemImageName: "clock.badge"
        )
        AppShortcut(
            intent: ScheduleForDayIntent(),
            phrases: [
                "Am I working \(\.$day) in \(.applicationName)",
                "What is my schedule \(\.$day) in \(.applicationName)",
            ],
            shortTitle: "Schedule for a Day",
            systemImageName: "calendar"
        )
    }
}
