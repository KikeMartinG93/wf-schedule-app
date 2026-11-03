import Foundation

/// CS Supervisor gate for the Keys tab (safe codes, liquor case, etc.).
/// Onboarding asks whether the user is a CS Sup; if so they enter a passcode.
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

    /// Passcode accepted — Keys tab is available.
    static var isUnlocked: Bool {
        UserDefaults.standard.bool(forKey: unlockedKey)
    }

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
