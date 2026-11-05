import Foundation

/// CS Supervisor gate for the Keys tab (safe codes, liquor case, etc.).
/// Keys is only offered when the local schedule includes Supervisor work.
/// Eligible people unlock with a store passcode (onboarding or Settings).
/// Access is local to this device — not synced.
enum CSSupAccess {
    private static let isCSSupKey = "csSupIsSupervisor"
    private static let unlockedKey = "csSupKeysUnlocked"
    private static let answeredKey = "csSupAnswered"

    /// Expected CS Sup passcode. Compared in memory only; never written to disk.
    private static let expectedPasscode = "cixpu8-rezhap-qEnrid"

    static let didChange = Notification.Name("CSSupAccessDidChange")

    /// User answered the CS Sup question during onboarding or Settings.
    static var hasAnswered: Bool {
        UserDefaults.standard.bool(forKey: answeredKey)
    }

    /// Whether the user said they are a CS Supervisor.
    static var isCSSup: Bool {
        UserDefaults.standard.bool(forKey: isCSSupKey)
    }

    /// Passcode accepted — Keys tab may show when the schedule still has Supervisor work.
    static var isUnlocked: Bool {
        UserDefaults.standard.bool(forKey: unlockedKey)
    }

    /// Supervisor (and Cash Office — remapped from Supervisor 6/7am starts).
    static func isSupervisorJob(_ job: String) -> Bool {
        job.caseInsensitiveCompare("Supervisor") == .orderedSame
            || job.caseInsensitiveCompare("Cash Office") == .orderedSame
    }

    /// True when the saved schedule includes at least one Supervisor shift.
    static var hasSupervisorShifts: Bool {
        let shifts = ScheduleStore.shared.load()?.shifts ?? []
        return shifts.contains { isSupervisorJob($0.job) }
    }

    /// Show unlock UI / onboarding CS steps / Keys mentions.
    static var shouldOfferKeys: Bool { hasSupervisorShifts }

    /// Keys tab: passcode unlocked and schedule still has Supervisor work.
    static var shouldShowKeysTab: Bool { isUnlocked && hasSupervisorShifts }

    static func saveAnswer(isCSSup: Bool) {
        UserDefaults.standard.set(true, forKey: answeredKey)
        UserDefaults.standard.set(isCSSup, forKey: isCSSupKey)
        if !isCSSup {
            UserDefaults.standard.set(false, forKey: unlockedKey)
        }
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// Returns `true` when the passcode matches and Keys access is granted.
    @discardableResult
    static func unlock(with passcode: String) -> Bool {
        let trimmed = passcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == expectedPasscode else { return false }
        UserDefaults.standard.set(true, forKey: answeredKey)
        UserDefaults.standard.set(true, forKey: isCSSupKey)
        UserDefaults.standard.set(true, forKey: unlockedKey)
        NotificationCenter.default.post(name: didChange, object: nil)
        return true
    }

    /// Revoke Keys access (Settings). Keeps the “is CS Sup” answer unless cleared.
    static func revokeKeysAccess() {
        UserDefaults.standard.set(false, forKey: unlockedKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: answeredKey)
        UserDefaults.standard.removeObject(forKey: isCSSupKey)
        UserDefaults.standard.removeObject(forKey: unlockedKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
