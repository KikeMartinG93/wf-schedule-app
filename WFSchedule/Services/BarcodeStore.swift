import Foundation
import WidgetKit

/// The user's TM ID. Held in the Keychain (see `SecureTMID`) and shared with
/// this device's widgets and the paired Watch; never shown as text anywhere in
/// the app. Older builds kept it in plain defaults, so the first read moves any
/// such copy into the Keychain and deletes it.
enum BarcodeStore {
    private static let legacyKey = "discountBarcodeNumber"
    private static let legacyGroup = "group.com.marting.WFM"

    static var value: String? {
        get {
            if let secure = SecureTMID.value { return secure }
            let legacy = UserDefaults(suiteName: legacyGroup)?.string(forKey: legacyKey)
                ?? UserDefaults.standard.string(forKey: legacyKey)
            guard let legacy, !legacy.isEmpty else { return nil }
            SecureTMID.value = legacy
            clearLegacy()
            return legacy
        }
        set {
            SecureTMID.value = newValue
            clearLegacy()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private static func clearLegacy() {
        UserDefaults(suiteName: legacyGroup)?.removeObject(forKey: legacyKey)
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }
}
