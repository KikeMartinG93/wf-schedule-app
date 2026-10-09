import Foundation
import WebKit

private struct SyncTimeoutError: LocalizedError {
    var errorDescription: String? { String(localized: "Sync timed out. Check your connection and try again.") }
}

/// Guards a `CheckedContinuation` against being resumed twice — a fatal
/// error — when two independent, un-awaited tasks are racing to resume the
/// same one and either could win. `@MainActor`-isolated (not a lock) since
/// both racing tasks are created from `@MainActor` code and inherit that
/// isolation, so access here is already serialized.
@MainActor
private final class SingleResume {
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func finish(returning value: Void) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: value)
    }

    func finish(throwing error: Error) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error)
    }
}

/// Single entry point that runs one full sync cycle: fetch → diff → persist →
/// calendar sync → notifications. Used by both the foreground "refresh now"
/// action and the background task (see BackgroundRefreshManager).
@MainActor
enum ScheduleSyncCoordinator {
    /// Hard ceiling on one sync attempt. Without this, a stalled network call
    /// or a hung EventKit/iCloud-calendar operation inside `applyFetchedSchedule`
    /// left `isSyncing` true forever — the UI spinner would just spin with no
    /// error and no updated "last synced" time, looking like a dead refresh.
    /// This guarantees the caller always gets a result (success or a clear
    /// timeout error) within a bounded time.
    private static let syncTimeout: TimeInterval = 25

    /// Non-blocking reentrancy guard: while `true`, a new `runSync` call
    /// backs off instead of starting overlapping work. Always cleared via
    /// `defer` in `runSync`, no matter how it exits — it can never get stuck.
    ///
    /// An earlier version of this guard instead tracked the in-flight
    /// operation's actual `Task` and AWAITED its completion before letting a
    /// new sync start, to close a race where a timed-out attempt's work kept
    /// running in the background (see `withTimeout` below) and could clash
    /// with a retry. That wait had no bound of its own: if the in-flight
    /// operation ever hung — for any reason — every sync attempt after it,
    /// forever, would block waiting on a task that would never finish, with
    /// no way out short of reinstalling the app. That is a confirmed bug:
    /// exactly what "the app is stuck on the first shifts it pulled, nothing
    /// updates" looks like from one bad sync onward. An unbounded wait that
    /// can permanently freeze every future sync is a far worse failure mode
    /// than the rare overlapping-write race it was preventing, so this is
    /// back to a simple flag.
    private static var isSyncing = false

    /// A real timeout, not just a race that happens to return early: the two
    /// `Task { }` blocks below are deliberately unstructured (created with
    /// plain `Task { }`, NOT `group.addTask` inside a `withThrowingTaskGroup`)
    /// because a task group's own call does not return until every child
    /// task has actually finished — including an uncancelled one, since
    /// cancellation in Swift is cooperative and EventKit calls inside
    /// `applyFetchedSchedule` never check it. Wrapping the operation in a
    /// task group (an earlier version of this code did) meant a genuinely
    /// stuck operation could make the "timeout" itself hang right along with
    /// it. Racing two independent, un-awaited tasks against a single
    /// continuation is what lets this function actually return at the
    /// deadline even when the operation doesn't; the loser keeps running
    /// fully detached rather than blocking anything further.
    private static func withTimeout(_ seconds: TimeInterval, operation: @escaping () async throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resume = SingleResume(continuation)
            Task {
                do {
                    try await operation()
                    resume.finish(returning: ())
                } catch {
                    resume.finish(throwing: error)
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                resume.finish(throwing: SyncTimeoutError())
            }
        }
    }

    private static func makeClient(for webView: WKWebView) -> any ScheduleFetching {
        switch SessionManager.shared.backend {
        case .innerview: InnerviewScheduleClient(webView: webView)
        case .ukg: UKGScheduleClient(webView: webView)
        }
    }

    private static func fetchAndApply(using client: any ScheduleFetching) async throws {
        let newShifts = try await client.fetchShifts()
        try await applyFetchedSchedule(newShifts)
        // Keeps the Keychain-saved cookie snapshot fresh across a long-lived
        // session, not just at login — see SessionManager.persistCurrentSessionSnapshot.
        SessionManager.shared.persistCurrentSessionSnapshot()
    }
    /// Minimum gap between automatic (non-forced) syncs — hard-caps foreground
    /// app opens and background wakes to 2x/day max, since each sync spins up
    /// a WKWebView load + network round trip. Pull-to-refresh and the manual
    /// refresh button pass `force: true` to bypass this — the user explicitly
    /// asked for fresh data.
    private static let minAutoSyncInterval: TimeInterval = 12 * 60 * 60
    private static let lastSyncAttemptKey = "lastScheduleSyncAttemptAt"

    static func runSync(force: Bool = false) async throws {
        // Demo mode has nothing to fetch, and must never touch the real
        // calendar, reminders, or the auto-sync throttle window.
        if DemoMode.isEnabled { return }
        if !force {
            let defaults = UserDefaults.standard
            if let last = defaults.object(forKey: lastSyncAttemptKey) as? Date,
               Date().timeIntervalSince(last) < minAutoSyncInterval {
                return
            }
            defaults.set(Date(), forKey: lastSyncAttemptKey)
        }

        guard !isSyncing else {
            // Never wait for the in-flight sync here — see `isSyncing`'s doc
            // comment for why that used to be able to freeze the app
            // permanently. A forced call (the user just tapped refresh)
            // surfaces that clearly instead of silently doing nothing.
            guard force else { return }
            throw SyncTimeoutError()
        }
        isSyncing = true
        defer { isSyncing = false }

        let sessionManager = SessionManager.shared

        if !sessionManager.isSessionValid() {
            // Try resuming from the cookies saved at the last sign-in before giving
            // up — for Innerview Login this is the ONLY way back in without the
            // user (there's no stored password to replay), and it's cheap when
            // there's nothing saved.
            let resumed = await sessionManager.attemptCookieRestore()

            // A background relaunch always starts with no in-memory webview/cookies
            // (the WKWebView session can't survive process death), so this branch
            // is hit on essentially every background wake. Without stored
            // credentials, attemptSilentReLogin is guaranteed to fail — there's
            // nothing to retry, so bail out quietly on an unforced (auto) sync
            // instead of notifying every single time the user backgrounds the
            // app. A forced sync (pull-to-refresh / the manual button) is the
            // user explicitly asking right now, so it throws instead of
            // silently doing nothing — the caller shows the error.
            if !resumed {
                guard sessionManager.hasStoredCredentials else {
                    guard force else { return }
                    throw UKGClientError.sessionExpired
                }

                let reLoggedIn = await sessionManager.attemptSilentReLogin()
                if !reLoggedIn {
                    NotificationService.notifyLoginRequired()
                    guard force else { return }
                    throw UKGClientError.sessionExpired
                }
            }
        }

        guard let webView = sessionManager.currentWebView() else {
            NotificationService.notifyLoginRequired()
            guard force else { return }
            throw UKGClientError.sessionExpired
        }
        let client = makeClient(for: webView)

        do {
            try await withTimeout(syncTimeout) { try await fetchAndApply(using: client) }
        } catch UKGClientError.sessionExpired {
            let reLoggedIn = await sessionManager.attemptSilentReLogin()
            guard reLoggedIn, let refreshedWebView = sessionManager.currentWebView() else {
                // A real fetch was already attempted and failed at this point —
                // always surface it, forced or not, so the UI can tell the user
                // why the schedule didn't update instead of looking like a no-op.
                NotificationService.notifyLoginRequired()
                throw UKGClientError.sessionExpired
            }
            let retryClient = makeClient(for: refreshedWebView)
            try await withTimeout(syncTimeout) { try await fetchAndApply(using: retryClient) }
        }
    }

    private static func applyFetchedSchedule(_ newShifts: [Shift]) async throws {
        let previous = ScheduleStore.shared.load()
        let result = ScheduleDiffer.diff(previous: previous, newShifts: newShifts)

        ScheduleStore.shared.save(result.nextSnapshot)

        let calendarSync = CalendarSyncService()
        try? await calendarSync.requestAccess()

        if !result.changes.isEmpty {
            try? calendarSync.apply(changes: result.changes)
            NotificationService.notifyChanges(result.changes)
            ChangeLogStore.shared.append(result.changes.map { ChangeLogEntry(change: $0) })
        }
        // Runs every sync, not just when there are diff-detected changes — see
        // reconcileTitles' doc comment for why.
        try? calendarSync.reconcileTitles(for: newShifts)
        // Also every sync (cheap, scoped to one calendar) — cleans up any
        // duplicate events left over from a reinstall wiping the on-disk
        // snapshot before this upsert logic existed, and is a harmless no-op
        // once there's nothing left to collapse.
        try? calendarSync.deduplicateEvents()

        NotificationService.rescheduleShiftReminders(for: newShifts)
        // A sync can reveal that a shift is on right now (or that it's been removed).
        BreakActivityManager.sync()
    }
}
