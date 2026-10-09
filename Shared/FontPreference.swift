import SwiftUI

/// Whether the app and its widgets use the rounded system font (the default) or
/// the standard one. Kept in the shared app-group defaults so the widgets and
/// Live Activity, which run in their own processes, read the same choice.
enum FontPreference {
    static let key = "useRoundedFont"
    static let store = UserDefaults(suiteName: "group.com.marting.WFM") ?? .standard

    static var rounded: Bool { store.object(forKey: key) as? Bool ?? true }
    static var design: Font.Design { rounded ? .rounded : .default }
}

/// High contrast mode: the whole app, its widgets and the Live Activity drop
/// color entirely and use only black, white and gray. Stored in the shared
/// defaults so the widgets (separate processes) can follow the app's choice.
enum ContrastPreference {
    static let key = "highContrastEnabled"
    static var high: Bool { FontPreference.store.bool(forKey: key) }
}
