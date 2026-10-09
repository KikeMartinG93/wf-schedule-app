import WidgetKit
import SwiftUI

/// The app publishes its schedule snapshot into the shared app-group container
/// (see `ScheduleStore.save`); the widget only ever reads it from there.
enum SharedSchedule {
    static let groupID = "group.com.marting.WFM"
    static let fileName = "schedule_snapshot.json"

    static func loadShifts() -> [Shift] {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
                .appendingPathComponent(fileName),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(ScheduleSnapshot.self, from: data)
        else { return [] }
        return snapshot.shifts
    }
}

struct NextShiftEntry: TimelineEntry {
    let date: Date
    let shift: Shift?
}

struct NextShiftProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextShiftEntry {
        NextShiftEntry(date: Date(), shift: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextShiftEntry) -> Void) {
        let now = Date()
        completion(NextShiftEntry(date: now, shift: Self.nextShift(after: now, in: SharedSchedule.loadShifts()) ?? (context.isPreview ? Self.sample : nil)))
    }

    /// One entry per hour for the next day so the "< 23h" countdown and the
    /// "D+2" day count stay accurate without the app running; the app also
    /// reloads timelines whenever a sync saves a new schedule.
    func getTimeline(in context: Context, completion: @escaping (Timeline<NextShiftEntry>) -> Void) {
        let shifts = SharedSchedule.loadShifts()
        let now = Date()
        let entries = (0..<24).map { hour -> NextShiftEntry in
            let date = now.addingTimeInterval(Double(hour) * 3600)
            return NextShiftEntry(date: date, shift: Self.nextShift(after: date, in: shifts))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(24 * 3600))))
    }

    static func nextShift(after date: Date, in shifts: [Shift]) -> Shift? {
        shifts
            .filter { $0.kind != .timeOff && $0.startTime > date }
            .min { $0.startTime < $1.startTime }
    }

    private static var sample: Shift {
        let start = Date().addingTimeInterval(22 * 3600)
        return Shift(ukgRecordId: nil, date: start, startTime: start, endTime: start.addingTimeInterval(8 * 3600),
                     job: "Supervisor", location: nil, kind: .regular, payCode: nil, notes: nil)
    }
}

struct NextShiftWidget: Widget {
    let kind = "NextShiftWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextShiftProvider()) { entry in
            NextShiftView(entry: entry).fontDesign(FontPreference.design)
        }
        .configurationDisplayName("Next Shift")
        .description("Your next shift and how long until it starts.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct NextShiftView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: NextShiftEntry
    /// Lets the in-app showcase draw a specific size (the environment value is read-only).
    var familyOverride: WidgetFamily? = nil

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                inline
            default:
                rectangular
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Next")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let shift = entry.shift {
                HStack {
                    Text(shift.job)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Text(Self.countdown(to: shift.startTime, from: entry.date))
                        .font(.system(size: 12, weight: .semibold))
                }
                HStack {
                    Text(Self.dayFormatter.string(from: shift.startTime))
                    Spacer(minLength: 4)
                    Text(shift.startTime.formatted(date: .omitted, time: .shortened))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
                Text("No upcoming shifts")
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        if let shift = entry.shift {
            Text("\(shift.job) \(Self.dayFormatter.string(from: shift.startTime)) \(shift.startTime.formatted(date: .omitted, time: .shortened))")
        } else {
            Text("No upcoming shifts")
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEMd")
        return formatter
    }()

    /// Under 24 hours away: "< 23h" (hours rounded up). Otherwise the number
    /// of calendar days away: "D+2".
    static func countdown(to start: Date, from now: Date) -> String {
        let seconds = start.timeIntervalSince(now)
        if seconds < 24 * 3600 {
            let hours = max(1, Int((seconds / 3600).rounded(.up)))
            return "< \(hours)h"
        }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: start)).day ?? 0
        return "D+\(days)"
    }
}
