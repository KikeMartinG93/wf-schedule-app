import Foundation

/// The app's language choice. `.system` follows the device; the others force
/// one language. The choice is written to `AppleLanguages` so the whole app
/// (formatted dates, notification text) uses it from the next launch, and the
/// root view also applies it as the SwiftUI locale so visible text switches
/// immediately.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, es

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    var locale: Locale {
        self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue)
    }

    static func apply(_ language: AppLanguage) {
        if language == .system {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        }
    }
}
