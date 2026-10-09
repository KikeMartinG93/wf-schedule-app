import Foundation
import Security

/// The TM ID lives in the Keychain, shared between the app and its widgets /
/// watch pieces through one access group, never in plain defaults. Readable
/// after the first unlock so Lock Screen widgets work while the phone is locked,
/// and never backed up or moved to another device.
enum SecureTMID {
    /// What the ID is replaced with anywhere it would otherwise be shown as text.
    static let masked = "*****"

    private static let service = "com.marting.WFM.tmid"
    private static let account = "tmID"
    private static let sharedGroup = "G7C5D28VAK.com.marting.WFM.shared"

    private static func query(useGroup: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if useGroup { query[kSecAttrAccessGroup as String] = sharedGroup }
        return query
    }

    /// Falls back to the process's own default group if the shared one isn't
    /// available (some simulator setups), so the app still works on its own.
    static var value: String? {
        get {
            for useGroup in [true, false] {
                var lookup = query(useGroup: useGroup)
                lookup[kSecReturnData as String] = true
                lookup[kSecMatchLimit as String] = kSecMatchLimitOne
                var item: CFTypeRef?
                if SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
                   let data = item as? Data, let text = String(data: data, encoding: .utf8), !text.isEmpty {
                    return text
                }
            }
            return nil
        }
        set {
            for useGroup in [true, false] { SecItemDelete(query(useGroup: useGroup) as CFDictionary) }
            guard let newValue, !newValue.isEmpty, let data = newValue.data(using: .utf8) else { return }
            for useGroup in [true, false] {
                var add = query(useGroup: useGroup)
                add[kSecValueData as String] = data
                add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                if SecItemAdd(add as CFDictionary, nil) == errSecSuccess { return }
            }
        }
    }
}
