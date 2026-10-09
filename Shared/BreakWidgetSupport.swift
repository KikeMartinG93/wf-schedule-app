import WidgetKit
import SwiftUI

struct BreakEntry: TimelineEntry {
    let date: Date
    let status: BreakStatus
    let pulseOn: Bool
}

struct BreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> BreakEntry {
        BreakEntry(date: Date(), status: .upcoming(due: Date().addingTimeInterval(30 * 60), number: 1, duration: 10), pulseOn: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (BreakEntry) -> Void) {
        let now = Date()
        let status = BreakStore.load().status(at: now)
        completion(BreakEntry(date: now, status: status == .none && context.isPreview ? placeholder(in: context).status : status, pulseOn: false))
    }

    /// One entry a minute for three hours keeps the bar and color moving (the
    /// countdown text itself ticks live). Widgets can't run a real animation, so
    /// the overdue pulse is approximated by alternating brightness on entries
    /// every 20 seconds for the first five minutes of being overdue; iOS may
    /// coalesce entries that close together.
    func getTimeline(in context: Context, completion: @escaping (Timeline<BreakEntry>) -> Void) {
        let plan = BreakStore.load()
        let now = Date()
        let horizon = now.addingTimeInterval(3 * 3600)

        // Nothing left to count toward: one static entry is enough, and it's
        // refreshed at the horizon (or right away when the app changes the plan).
        // Without this, an empty plan still rendered 180 identical entries.
        switch plan.status(at: now) {
        case .none, .allTaken:
            completion(Timeline(entries: [BreakEntry(date: now, status: plan.status(at: now), pulseOn: false)], policy: .after(horizon)))
            return
        case .upcoming, .overdue:
            break
        }

        var times = Set<Date>([now])
        for minute in 1...180 { times.insert(now.addingTimeInterval(Double(minute) * 60)) }

        var pulseStarts: [Date] = []
        if case .overdue = plan.status(at: now) { pulseStarts.append(now) }
        for slot in plan.slots where !slot.isTaken(on: now) {
            let due = slot.dueDate(on: now)
            if due > now, due < horizon {
                times.insert(due)
                pulseStarts.append(due)
            }
        }
        for start in pulseStarts {
            for step in 0..<15 { times.insert(start.addingTimeInterval(Double(step) * 20)) }
        }

        let entries = times.sorted().map { time -> BreakEntry in
            let status = plan.status(at: time)
            var pulseOn = false
            if case .overdue = status { pulseOn = Int(time.timeIntervalSince1970 / 20) % 2 == 0 }
            return BreakEntry(date: time, status: status, pulseOn: pulseOn)
        }
        completion(Timeline(entries: entries, policy: .after(horizon)))
    }
}

/// Color for a break state: green when it's far off, through amber, to red as
/// it gets close and once it's overdue. Grey when there's nothing to count.
enum BreakWidgetTint {
    static func color(for entry: BreakEntry) -> Color {
        switch entry.status {
        case .none: Color.gray
        case .allTaken: BreakStyle.color(remaining: BreakStyle.colorWindow)
        case .upcoming(let due, _, _): BreakStyle.color(remaining: due.timeIntervalSince(entry.date))
        case .overdue: BreakStyle.color(remaining: nil)
        }
    }
}

/// Home Screen backdrop for the small break widget: the surface color with a
/// wash of the state color in one corner, so the widget itself reads green,
/// amber or red at a glance. Public so the in-app gallery draws the same thing.
struct BreakWidgetBackground: View {
    let entry: BreakEntry

    var body: some View {
        let tint = BreakWidgetTint.color(for: entry)
        ZStack {
            #if os(watchOS)
            Color.black
            #else
            Color(uiColor: .systemBackground)
            #endif
            if !ContrastPreference.high {
                LinearGradient(colors: [tint.opacity(0.34), tint.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
}

/// A ring that drains toward the break (full at two hours out, solid when overdue).
private struct BreakRing<Center: View>: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat
    var glow = false
    var dimmed = false
    @ViewBuilder var center: () -> Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(progress, 0.001))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: glow ? color.opacity(0.55) : .clear, radius: lineWidth * 0.5)
                .opacity(dimmed ? 0.4 : 1)
                .widgetAccentable()
            center()
        }
        .padding(lineWidth / 2)
    }
}

/// Time until the next break, or how long it's overdue. Small (Home Screen):
/// a ring around the countdown. Rectangular (Lock Screen / watch): a compact ring
/// beside the countdown. Full color only shows on the Home Screen; the Lock
/// Screen and most watch faces recolor widgets to one tint, where the ring's
/// length and the pulse carry the message.
struct BreakWidgetView: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.widgetFamily) private var environmentFamily
    let entry: BreakEntry
    /// Lets the in-app showcase draw a specific size (the environment value is read-only).
    var familyOverride: WidgetFamily? = nil

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    #if os(watchOS)
    private var isSmall: Bool { false }
    #else
    private var isSmall: Bool { family == .systemSmall }
    #endif

    private var fullColor: Bool { renderingMode == .fullColor }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if isSmall && fullColor { BreakWidgetBackground(entry: entry) } else { Color.clear }
            }
    }

    private var tint: Color { fullColor ? BreakWidgetTint.color(for: entry) : Color.primary }

    @ViewBuilder
    private var content: some View {
        switch entry.status {
        case .none:
            message(symbol: "cup.and.saucer", title: "No breaks set", detail: "Set your breaks in the app", progress: 0)
        case .allTaken:
            message(symbol: "checkmark", title: "All breaks taken", detail: nil, progress: 1)
        case .upcoming(let due, let number, let duration):
            countdown(label: "Break in", due: due, number: number, duration: duration, overdue: false)
        case .overdue(let due, let number, let duration):
            countdown(label: "Overdue", due: due, number: number, duration: duration, overdue: true)
        }
    }

    // MARK: - Countdown

    @ViewBuilder
    private func countdown(label: LocalizedStringKey, due: Date, number: Int, duration: Int, overdue: Bool) -> some View {
        let remaining = due.timeIntervalSince(entry.date)
        let progress = overdue ? 1 : BreakStyle.fill(remaining: remaining)
        let dimmed = overdue && entry.pulseOn
        if isSmall {
            smallCountdown(label: label, due: due, number: number, duration: duration,
                           overdue: overdue, progress: progress, dimmed: dimmed)
        } else {
            compactCountdown(label: label, due: due, number: number, duration: duration,
                             overdue: overdue, progress: progress, dimmed: dimmed)
        }
    }

    private func smallCountdown(label: LocalizedStringKey, due: Date, number: Int, duration: Int,
                                overdue: Bool, progress: Double, dimmed: Bool) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
                    .widgetAccentable()
                Text("Break \(number)")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 2)
                Text("\(duration) min")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            BreakRing(progress: progress, color: tint, lineWidth: 9, glow: fullColor, dimmed: dimmed) {
                VStack(spacing: 0) {
                    Text(due, style: .timer)
                        .font(.system(.title3, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 74)
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(overdue && fullColor ? tint : Color.secondary)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
        }
    }

    private func compactCountdown(label: LocalizedStringKey, due: Date, number: Int, duration: Int,
                                  overdue: Bool, progress: Double, dimmed: Bool) -> some View {
        HStack(spacing: 10) {
            BreakRing(progress: progress, color: tint, lineWidth: 5, dimmed: dimmed) {
                Image(systemName: overdue ? "exclamationmark" : "cup.and.saucer.fill")
                    .font(.system(size: 14, weight: .bold))
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(overdue && fullColor ? tint : Color.secondary)
                Text(due, style: .timer)
                    .font(.system(.title3, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Break \(number) · \(duration) min")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Empty states

    @ViewBuilder
    private func message(symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey?, progress: Double) -> some View {
        if isSmall {
            VStack(spacing: 8) {
                BreakRing(progress: progress, color: tint, lineWidth: 9, glow: fullColor) {
                    Image(systemName: symbol)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(progress > 0 ? tint : Color.secondary)
                }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                VStack(spacing: 1) {
                    Text(title).font(.footnote.weight(.semibold))
                    if let detail {
                        Text(detail).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            }
        } else {
            HStack(spacing: 10) {
                BreakRing(progress: progress, color: tint, lineWidth: 5) {
                    Image(systemName: symbol).font(.system(size: 14, weight: .bold))
                }
                .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    if let detail {
                        Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
