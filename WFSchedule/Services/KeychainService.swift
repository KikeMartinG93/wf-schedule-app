import Foundation
import Security

/// Thin wrapper around SecItem for storing the UKG username/password used for
/// silent re-login. Values never leave the device; they're only replayed into
/// the same WKWebView-hosted UKG login page used for interactive login.
enum KeychainService {
    private static let service = "com.example.wfschedule.ukg"

    private static func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func set(_ value: String, account: String) {
        setData(Data(value.utf8), account: account)
    }

    static func get(account: String) -> String? {
        guard let data = getData(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setData(_ value: Data, account: String) {
        var q = query(account: account)
        if SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(q as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        } else {
            q[kSecValueData as String] = value
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(q as CFDictionary, nil)
        }
    }

    static func getData(account: String) -> Data? {
        var q = query(account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return data
    }

    static func delete(account: String) {
        SecItemDelete(query(account: account) as CFDictionary)
    }

    enum Account {
        static let username = "ukg_username"
        static let password = "ukg_password"
        /// The full mykronos.com-domain cookie jar from the last successful login
        /// (interactive or silent). See `SessionManager.attemptCookieRestore`.
        static let sessionCookies = "ukg_session_cookies"
        /// The same idea for Innerview Login: its own cookies plus the identity
        /// providers' (see `InnerviewEndpoints.isSessionCookie`).
        static let innerviewSessionCookies = "innerview_session_cookies"
    }
}
