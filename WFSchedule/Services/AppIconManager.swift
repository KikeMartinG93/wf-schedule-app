import UIKit

/// Keeps the Home Screen icon in step with the chosen color theme: each theme
/// except the default green has an alternate icon with that theme's color as the
/// background. iOS shows its own "You have changed the icon" notice when this runs.
///
/// There's also one hidden extra, the classic icon. Ten quick taps on the version
/// number in Settings unlock a "WF Icon" toggle that switches it on and off. While
/// it's on, changing themes leaves the icon alone.
enum AppIconManager {
    static let classicName = "AppIcon-classic"
    static let classicKey = "classicIconActive"
    static let unlockedKey = "classicIconUnlocked"

    static var isClassicActive: Bool { UserDefaults.standard.bool(forKey: classicKey) }

    @MainActor
    static func apply(themeID: String) {
        guard !isClassicActive else { return }
        setIcon(themeIconName(themeID))
    }

    @MainActor
    static func setClassic(_ enabled: Bool, themeID: String) {
        UserDefaults.standard.set(enabled, forKey: classicKey)
        setIcon(enabled ? classicName : themeIconName(themeID))
    }

    private static func themeIconName(_ themeID: String) -> String? {
        themeID == "green" ? nil : "AppIcon-\(themeID)"
    }

    @MainActor
    private static func setIcon(_ name: String?) {
        let application = UIApplication.shared
        guard application.supportsAlternateIcons, application.alternateIconName != name else { return }
        application.setAlternateIconName(name)
    }
}
