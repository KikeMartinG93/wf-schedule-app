import Foundation

enum ScheduleChangeKind {
    case new(Shift)
    case changed(old: Shift, new: Shift)
    case removed(Shift)
}

struct ScheduleDiffResult {
    var changes: [ScheduleChangeKind]
    var nextSnapshot: ScheduleSnapshot
}

/// Shifts are matched by (date, startTime, endTime, job) — see Shift.matchKey.
/// A shift missing from the new fetch is only reported as "removed" after it has
/// been missing on 2 consecutive successful fetches, to absorb transient UKG/network
/// blips without firing a false removal alert.
///
/// UKG's single-request window is only today → a few weeks ahead, so past shifts
/// would vanish on every login refresh if the snapshot were replaced wholesale.
/// Shifts whose day falls outside that fetch window stay on disk as local history
/// and are never treated as removals just because UKG didn't return them.
enum ScheduleDiffer {
    static func diff(
        previous: ScheduleSnapshot?,
        newShifts: [Shift],
        fetchedAt: Date = Date(),
        fetchWindowStart: Date,
        fetchWindowEnd: Date,
        calendar: Calendar = .current
    ) -> ScheduleDiffResult {
        var changes: [ScheduleChangeKind] = []

        let windowStart = calendar.startOfDay(for: fetchWindowStart)
        let windowEnd = calendar.startOfDay(for: fetchWindowEnd)

        func dayKey(for shift: Shift) -> Date {
            calendar.startOfDay(for: shift.date)
        }

        func isInFetchWindow(_ shift: Shift) -> Bool {
            let day = dayKey(for: shift)
            return day >= windowStart && day <= windowEnd
        }

        let previousShifts = previous?.shifts ?? []
        let historyShifts = previousShifts.filter { !isInFetchWindow($0) }
        let previousInWindow = previousShifts.filter(isInFetchWindow)

        // `Dictionary(uniqueKeysWithValues:)` traps (crashes the whole app,
        // uncatchable) if two shifts ever map to the same id — plausible
        // since UKG can report the same shift under both `regularShifts` and
        // `transferShifts`. `Dictionary(_:uniquingKeysWith:)` keeps this
        // resilient to that instead of turning a data quirk into a hard
        // crash that silently kills every sync from that point on.
        let previousById = Dictionary(previousInWindow.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let newById = Dictionary(newShifts.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let historyById = Dictionary(historyShifts.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })

        for shift in newShifts {
            if let old = previousById[shift.id], old != shift {
                changes.append(.changed(old: old, new: shift))
            }
        }

        // Shifts whose id matched nothing on the other side at all — these
        // are either a genuine new/removed shift, or (see the pairing pass
        // below) the SAME shift with an edited time. Since `Shift.id` is
        // derived from date+start+end+job, editing a shift's time — the most
        // common edit there is — changes its id entirely, so without this it
        // would show up here as one unrelated "new" plus one separately
        // 2-fetch-debounced "removed" instead of a single coherent "changed"
        // entry, and the old calendar event would sit next to the new one
        // until that debounce finally confirmed the old id gone.
        var orphanedNew = newShifts.filter { previousById[$0.id] == nil }
        var orphanedOld = previousInWindow.filter { newById[$0.id] == nil }

        // Pair same-day orphans as an edit rather than an unrelated
        // add+remove — but only when the pairing is unambiguous (exactly one
        // orphan on each side for that day); if a day has several orphaned
        // shifts, which old one matches which new one genuinely can't be
        // inferred from this data, so those fall through to the ordinary
        // new/removed handling below instead of risking an incorrect
        // pairing.
        //
        // Deliberately NOT keyed on job too: a shift's job is exactly the
        // kind of thing an edit can change (e.g. Cash Office reassigned to
        // Supervisor) — same as time, requiring it to match would silently
        // defeat the pairing for precisely the edits most worth catching.
        let orphanedOldByDay = Dictionary(grouping: orphanedOld, by: dayKey)
        let orphanedNewByDay = Dictionary(grouping: orphanedNew, by: dayKey)

        var pairedOldIDs: Set<String> = []
        var pairedNewIDs: Set<String> = []
        for (day, oldGroup) in orphanedOldByDay {
            guard oldGroup.count == 1, let newGroup = orphanedNewByDay[day], newGroup.count == 1 else { continue }
            let old = oldGroup[0]
            let new = newGroup[0]
            changes.append(.changed(old: old, new: new))
            pairedOldIDs.insert(old.id)
            pairedNewIDs.insert(new.id)
        }
        orphanedOld.removeAll { pairedOldIDs.contains($0.id) }
        orphanedNew.removeAll { pairedNewIDs.contains($0.id) }

        for shift in orphanedNew {
            changes.append(.new(shift))
        }

        var pendingMisses = previous?.pendingRemovalMisses ?? [:]
        var confirmedRemovals: [Shift] = []

        // History outside the fetch window is kept locally on purpose — never
        // count it as a "miss" just because UKG's short window omitted it.
        for id in historyById.keys {
            pendingMisses.removeValue(forKey: id)
        }

        for old in orphanedOld {
            let misses = (pendingMisses[old.id] ?? 0) + 1
            if misses >= 2 {
                confirmedRemovals.append(old)
                pendingMisses.removeValue(forKey: old.id)
            } else {
                pendingMisses[old.id] = misses
            }
        }

        // Anything present in this fetch, or just paired off as an edit, is
        // by definition not currently missing.
        for shift in newShifts {
            pendingMisses.removeValue(forKey: shift.id)
        }
        for id in pairedOldIDs {
            pendingMisses.removeValue(forKey: id)
        }

        for shift in confirmedRemovals {
            changes.append(.removed(shift))
        }

        // Keep one-miss in-window shifts so a single flaky fetch doesn't wipe
        // them; drop them only after the second consecutive miss above.
        let pendingKept = orphanedOld.filter { pendingMisses[$0.id] != nil }

        // Local history first, then the live window (new fetch + still-pending
        // misses). If UKG ever returns a shift that overlaps a history id,
        // the fresh copy wins.
        var mergedById = historyById
        for shift in newShifts {
            mergedById[shift.id] = shift
        }
        for shift in pendingKept {
            if mergedById[shift.id] == nil {
                mergedById[shift.id] = shift
            }
        }

        let nextSnapshot = ScheduleSnapshot(
            fetchedAt: fetchedAt,
            shifts: mergedById.values.sorted { $0.startTime < $1.startTime },
            pendingRemovalMisses: pendingMisses
        )

        return ScheduleDiffResult(changes: changes, nextSnapshot: nextSnapshot)
    }
}
