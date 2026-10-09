import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// What the Lock Screen is showing right now. Worked out from the activity's state
/// at render time, because nothing runs to update it at the moments that matter:
/// the system flips `isStale` when the countdown reaches its date, and this turns
/// that flip (or any later render) into the next look.
enum BreakActivityFace {
    case waiting(kind: BreakKind, since: Date, until: Date)
    case ready(kind: BreakKind, stage: Int)
    case running(kind: BreakKind, since: Date, until: Date)
    /// Nothing more to offer: the last break is done, or the shift is.
    case done(kind: BreakKind?, shiftOver: Bool)

    static func make(state: BreakActivityAttributes.ContentState, isStale: Bool, now: Date = Date()) -> BreakActivityFace {
        if state.shiftEnd <= now { return .done(kind: nil, shiftOver: true) }
        let due = isStale || state.at <= now
        switch state.mode {
        case .waiting:
            return due ? .ready(kind: state.kind, stage: state.stage) : .waiting(kind: state.kind, since: state.start, until: state.at)
        case .running:
            if !due { return .running(kind: state.kind, since: state.start, until: state.at) }
            // The timer is up; show what comes next.
            guard let kind = state.nextKind, let stage = state.nextStage, let at = state.nextAt else {
                return .done(kind: state.kind, shiftOver: false)
            }
            return at <= now ? .ready(kind: kind, stage: stage) : .waiting(kind: kind, since: max(state.at, now), until: at)
        }
    }
}

/// Lock Screen banner and Dynamic Island for a shift's breaks: a countdown to the
/// next one, a Start button once it's due, and a countdown while it runs.
struct BreakLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BreakActivityAttributes.self) { context in
            BreakActivityBanner(face: BreakActivityFace.make(state: context.state, isStale: context.isStale))
                .padding(16)
                .activityBackgroundTint(nil)
                .widgetURL(URL(string: "wfschedule://breaks"))
                .fontDesign(FontPreference.design)
        } dynamicIsland: { context in
            let face = BreakActivityFace.make(state: context.state, isStale: context.isStale)
            let tint = BreakActivityStyle.tint(face)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(BreakActivityStyle.title(face), systemImage: BreakActivityStyle.icon(face))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if case .running(let kind, _, _) = face {
                        Text("\(kind.minutes) min")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(tint, in: Capsule())
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if let range = BreakActivityStyle.countdownRange(face) {
                            HStack(spacing: 10) {
                                Image(systemName: BreakActivityStyle.icon(face))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.black)
                                    .frame(width: 24, height: 24)
                                    .background(tint, in: Circle())
                                BreakMeter(since: range.lowerBound, until: range.upperBound)
                                Text(timerInterval: range, countsDown: true)
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 54, alignment: .trailing)
                            }
                        } else {
                            BreakActivityAction(face: face)
                        }
                        if let message = BreakActivityStyle.message(face) {
                            message
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.center)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: BreakActivityStyle.icon(face)).foregroundStyle(tint)
            } compactTrailing: {
                if let range = BreakActivityStyle.countdownRange(face) {
                    Text(timerInterval: range, countsDown: true)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 58)
                }
            } minimal: {
                Image(systemName: BreakActivityStyle.icon(face)).foregroundStyle(tint)
            }
            .keylineTint(tint)
        }
    }
}

enum BreakActivityStyle {
    static func tint(_ face: BreakActivityFace) -> Color {
        if ContrastPreference.high { return Color.primary }
        switch face {
        case .waiting, .done: return Color(hue: BreakStyle.greenHue, saturation: 0.85, brightness: 0.8)
        case .ready: return Color(hue: 0.09, saturation: 0.9, brightness: 0.95)
        case .running: return Color(hue: BreakStyle.greenHue, saturation: 0.85, brightness: 0.8)
        }
    }

    static func icon(_ face: BreakActivityFace) -> String {
        switch face {
        case .waiting(let kind, _, _), .ready(let kind, _), .running(let kind, _, _):
            return kind == .lunch ? "fork.knife" : "cup.and.saucer.fill"
        case .done: return "checkmark.circle.fill"
        }
    }

    static func title(_ face: BreakActivityFace) -> LocalizedStringKey {
        switch face {
        case .waiting(let kind, _, _): return kind == .lunch ? "Lunch in" : "Break in"
        case .ready(let kind, _): return kind == .lunch ? "Time for lunch" : "Time for a break"
        case .running(let kind, _, _): return kind == .lunch ? "Lunch" : "Break"
        case .done(let kind, let shiftOver):
            if shiftOver { return "Shift over" }
            return kind == .lunch ? "Lunch over" : "Break over"
        }
    }

    /// The stretch a countdown text should run through, if this look has one.
    static func countdownRange(_ face: BreakActivityFace) -> ClosedRange<Date>? {
        switch face {
        case .waiting(_, let since, let until), .running(_, let since, let until): return since...until
        case .ready, .done: return nil
        }
    }

    /// The line under the bar: when the running break is over, or when the next
    /// one can be started.
    static func message(_ face: BreakActivityFace) -> Text? {
        switch face {
        case .running(_, _, let until): return Text("Ends at \(until, style: .time)")
        case .waiting(_, _, let until): return Text("Available at \(until, style: .time)")
        case .ready, .done: return nil
        }
    }

    static func startTitle(_ kind: BreakKind) -> LocalizedStringKey {
        kind == .lunch ? "Start 30 min lunch" : "Start 10 min break"
    }
}

/// The button, or the drain bar while a timer runs.
private struct BreakActivityAction: View {
    let face: BreakActivityFace

    var body: some View {
        switch face {
        case .ready(let kind, let stage):
            Button(intent: StartBreakIntent(stage: stage)) {
                Label(BreakActivityStyle.startTitle(kind), systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(BreakActivityStyle.tint(face))
        case .running(_, let since, let until), .waiting(_, let since, let until):
            BreakMeter(since: since, until: until)
        case .done:
            EmptyView()
        }
    }
}

private struct BreakActivityBanner: View {
    let face: BreakActivityFace

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(BreakActivityStyle.title(face), systemImage: BreakActivityStyle.icon(face))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BreakActivityStyle.tint(face))
                Spacer()
                if let range = BreakActivityStyle.countdownRange(face) {
                    Text(timerInterval: range, countsDown: true)
                        .font(.system(.largeTitle, weight: .bold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .minimumScaleFactor(0.6)
                }
            }
            BreakActivityAction(face: face)
            if let message = BreakActivityStyle.message(face) {
                message
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A bar that drains from right to left as the time runs out: green for most of
/// it, then amber, then red as it reaches zero. A progress view can't change color
/// by itself, and nothing is running to change it, so the bar is a row of small
/// ones — each drains over its own slice of the time, the leftmost (last to empty)
/// is red and the rightmost (first) is green. The system drives every one of them,
/// so the shift from green to red happens with the app closed.
struct BreakMeter: View {
    let since: Date
    let until: Date

    private let segments = 24

    var body: some View {
        let slice = until.timeIntervalSince(since) / Double(segments)
        HStack(spacing: 1.5) {
            ForEach(0..<segments, id: \.self) { index in
                // index 0 is the leftmost segment and empties last.
                let end = until.addingTimeInterval(-slice * Double(index))
                let begin = end.addingTimeInterval(-slice)
                ProgressView(timerInterval: begin...end, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(color(at: index))
            }
        }
        .frame(height: 12)
    }

    /// Red at the far left, easing through amber to green by about the third segment.
    private func color(at index: Int) -> Color {
        if ContrastPreference.high { return Color.primary }
        let progress = min(Double(index) / 7.0, 1)
        return Color(hue: BreakStyle.greenHue * progress, saturation: 0.85, brightness: 0.9 - 0.1 * progress)
    }
}
