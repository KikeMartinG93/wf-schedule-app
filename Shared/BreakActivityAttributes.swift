import ActivityKit
import Foundation

/// Live Activity for a shift's breaks. It only exists while there's a shift on
/// (see `BreakActivityManager`) and walks through the shift's rhythm — see
/// `BreakRhythm` — one prompt at a time.
///
/// Everything the Lock Screen needs to change on its own is in the state, because
/// nothing is running to change it: while `.waiting` the system flips `isStale` at
/// `at` (the app sets `staleDate` to it) and the view swaps the countdown for the
/// Start button; while `.running` it flips at the end of the timer, and the view
/// shows what comes next, which `next…` already carries.
struct BreakActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Mode: String, Codable, Hashable {
            case waiting
            case running
        }

        var mode: Mode
        var kind: BreakKind
        /// Index in the shift's break list — what the Start button asks for.
        var stage: Int
        /// `.waiting`: when the button appears. `.running`: when the timer ends.
        var at: Date
        /// `.running`: when the timer began (the progress bar starts here).
        var start: Date
        /// `.running`: the break that follows, if any, so the view can show it
        /// once the timer is up without the app being involved.
        var nextKind: BreakKind?
        var nextStage: Int?
        var nextAt: Date?
        var shiftEnd: Date
    }
}
