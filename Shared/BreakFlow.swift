import Foundation

enum BreakKind: String, Codable, Hashable {
    case rest
    case lunch

    var minutes: Int {
        switch self {
        case .rest: 10
        case .lunch: 30
        }
    }
}

/// One prompt in a shift: what to offer, and how far into the shift it appears.
struct PlannedBreak: Codable, Hashable {
    var kind: BreakKind
    var promptAt: Date
}

/// The rhythm of a shift's breaks, set from the shift's own start rather than
/// from clock times: a 10 minute break, a 30 minute lunch once four hours have
/// gone by, and another 10 minute break at six hours. Each is only offered if
/// it would still fit before the shift ends.
enum BreakRhythm {
    static let offsets: [(kind: BreakKind, hours: Double)] = [(.rest, 0), (.lunch, 4), (.rest, 6)]

    static func plan(shiftStart: Date, shiftEnd: Date) -> [PlannedBreak] {
        offsets.compactMap { entry in
            let promptAt = shiftStart.addingTimeInterval(entry.hours * 3600)
            let finishes = promptAt.addingTimeInterval(TimeInterval(entry.kind.minutes) * 60)
            return finishes <= shiftEnd ? PlannedBreak(kind: entry.kind, promptAt: promptAt) : nil
        }
    }
}

/// Where one shift's breaks stand: which have been started, and the running one's
/// clock. Kept as plain data so it can live in the shared app-group defaults —
/// the Lock Screen buttons run in the app's process and read it from there.
struct BreakFlow: Codable, Equatable {
    struct Run: Codable, Equatable {
        var startedAt: Date
        var endsAt: Date
        var finished: Bool
        var alarmID: UUID?
    }

    var shiftID: String
    var shiftStart: Date
    var shiftEnd: Date
    var breaks: [PlannedBreak]
    var runs: [Int: Run] = [:]

    static func make(shiftStart: Date, shiftEnd: Date) -> BreakFlow {
        BreakFlow(
            shiftID: ISO8601DateFormatter().string(from: shiftStart),
            shiftStart: shiftStart,
            shiftEnd: shiftEnd,
            breaks: BreakRhythm.plan(shiftStart: shiftStart, shiftEnd: shiftEnd)
        )
    }

    /// A break is used up once it's been started — or once the NEXT one's time
    /// has come without it being started, so skipping the first break doesn't
    /// leave it waiting to reappear after lunch.
    private func isConsumed(_ index: Int, at now: Date) -> Bool {
        if runs[index] != nil { return true }
        return breaks.indices.contains { later in
            later > index && (runs[later] != nil || now >= breaks[later].promptAt)
        }
    }

    /// A timer counts as running until its time is up; after that it's done
    /// whether or not anyone tapped the alarm's Stop.
    private func runningIndex(at now: Date) -> Int? {
        runs.filter { !$0.value.finished && now < $0.value.endsAt }.keys.sorted().first
    }

    /// What the Lock Screen should be showing right now — or `nil` once the shift
    /// is over or every break has been taken, which is when the activity ends.
    func contentState(at now: Date) -> BreakActivityAttributes.ContentState? {
        guard now < shiftEnd else { return nil }

        if let index = runningIndex(at: now), let run = runs[index] {
            let next = breaks.indices.first { $0 > index && !isConsumedAfter(run: index, endingAt: run.endsAt, candidate: $0) }
            return BreakActivityAttributes.ContentState(
                mode: .running,
                kind: breaks[index].kind,
                stage: index,
                at: run.endsAt,
                start: run.startedAt,
                nextKind: next.map { breaks[$0].kind },
                nextStage: next,
                nextAt: next.map { breaks[$0].promptAt },
                shiftEnd: shiftEnd
            )
        }

        guard let index = breaks.indices.first(where: { !isConsumed($0, at: now) }) else { return nil }
        return BreakActivityAttributes.ContentState(
            mode: .waiting,
            kind: breaks[index].kind,
            stage: index,
            at: breaks[index].promptAt,
            start: index > 0 ? breaks[index - 1].promptAt : shiftStart,
            nextKind: nil,
            nextStage: nil,
            nextAt: nil,
            shiftEnd: shiftEnd
        )
    }

    /// Whether `candidate` will already have been passed over by the time a run
    /// that ends at `time` is done.
    private func isConsumedAfter(run: Int, endingAt time: Date, candidate: Int) -> Bool {
        if runs[candidate] != nil { return true }
        return breaks.indices.contains { later in
            later > candidate && (runs[later] != nil || time >= breaks[later].promptAt)
        }
    }

    /// When the system should flip the activity to its next look with nobody
    /// touching it: the prompt time while waiting, the end of the timer while
    /// running.
    func staleDate(for state: BreakActivityAttributes.ContentState) -> Date {
        state.at
    }

    mutating func start(stage: Int, at now: Date, alarmID: UUID?) -> Bool {
        guard breaks.indices.contains(stage), runs[stage] == nil, runningIndex(at: now) == nil else { return false }
        let ends = now.addingTimeInterval(TimeInterval(breaks[stage].kind.minutes) * 60)
        runs[stage] = Run(startedAt: now, endsAt: ends, finished: false, alarmID: alarmID)
        return true
    }

    mutating func finish(stage: Int) {
        guard var run = runs[stage] else { return }
        run.finished = true
        runs[stage] = run
    }
}
