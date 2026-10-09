import Foundation

/// The TM ID on the watch: in the Keychain (see `SecureTMID`), shared by the
/// Watch app and its complication. Getting the value FROM the iPhone onto the
/// watch is `WatchBarcodeReceiver`'s job (WatchConnectivity). Any copy an older
/// build left in plain shared defaults is moved into the Keychain and deleted.
enum WatchBarcodeStore {
    static let appGroupID = "group.com.marting.WFM"
    private static let legacyKey = "discountBarcodeNumber"

    private static var legacyDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static var value: String? {
        get {
            if let secure = SecureTMID.value { return secure }
            guard let legacy = legacyDefaults?.string(forKey: legacyKey), !legacy.isEmpty else { return nil }
            SecureTMID.value = legacy
            legacyDefaults?.removeObject(forKey: legacyKey)
            return legacy
        }
        set {
            SecureTMID.value = newValue
            legacyDefaults?.removeObject(forKey: legacyKey)
        }
    }
}
