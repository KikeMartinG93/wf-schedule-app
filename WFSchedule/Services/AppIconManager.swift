import UIKit

/// Keeps the Home Screen icon in step with the chosen color theme.
///
/// - Default: calendar icon whose background (and deep chrome) match the theme.
/// - "WF Icon" (classic wordmark): same accent backgrounds on the Whole Foods
///   wordmark. Ten quick taps on the version number in Settings unlocks that mode.
///
/// iOS shows its own "You have changed the icon" notice when this runs.
enum AppIconManager {
    static let classicName = "AppIcon-classic"
    static let classicKey = "classicIconActive"
    static let unlockedKey = "classicIconUnlocked"

    static var isClassicActive: Bool { UserDefaults.standard.bool(forKey: classicKey) }

    /// Themes that ship an alternate icon (everything except the catalog primary green).
    private static let alternateThemeIDs: Set<String> = [
        "halloween", "blue", "purple", "rose", "amber",
        "teal", "crimson", "indigo", "colorful", "rainbow",
    ]

    @MainActor
    static func apply(themeID: String) {
        setIcon(iconName(themeID: themeID, classic: isClassicActive))
    }

    @MainActor
    static func setClassic(_ enabled: Bool, themeID: String) {
        UserDefaults.standard.set(enabled, forKey: classicKey)
        setIcon(iconName(themeID: themeID, classic: enabled))
    }

    /// Calendar: primary `AppIcon` for green, else `AppIcon-<id>`.
    /// Classic wordmark: `AppIcon-classic` for green, else `AppIcon-classic-<id>`.
    private static func iconName(themeID: String, classic: Bool) -> String? {
        if classic {
            if themeID == "green" { return classicName }
            guard alternateThemeIDs.contains(themeID) else { return classicName }
            return "AppIcon-classic-\(themeID)"
        }
        if themeID == "green" { return nil }
        guard alternateThemeIDs.contains(themeID) else { return nil }
        return "AppIcon-\(themeID)"
    }

    @MainActor
    private static func setIcon(_ name: String?) {
        let application = UIApplication.shared
        guard application.supportsAlternateIcons else { return }
        // Compare after normalizing: primary icon is reported as `nil`.
        let current = application.alternateIconName
        guard current != name else { return }
        application.setAlternateIconName(name) { error in
            if let error {
                #if DEBUG
                print("AppIconManager: failed to set icon \(name ?? "primary"): \(error)")
                #endif
            }
        }
    }
}
