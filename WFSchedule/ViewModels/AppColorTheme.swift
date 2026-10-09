import SwiftUI
import WidgetKit

/// One selectable app color scheme: a background gradient tint, the accent
/// used for selection state (tab bar, buttons, selected calendar day), and a
/// holiday-pay marker color. Kept as one coordinated triple rather than
/// separate pickers so every combination on screen is intentional — the same
/// relationship the original fixed green tint/accent/sage set had. Each
/// theme's `holidayPay` is a muted tone hue-shifted ~45° off that theme's own
/// `accent` (the same relationship the original sage had to the original
/// green accent), so it always reads as visually distinct from "selected"
/// while still sitting in that theme's family rather than looking bolted on.
struct AppColorTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let backgroundTint: Color
    let accent: Color
    let holidayPay: Color
    /// Overrides for the Cash Office / Supervisor job-badge colors (see
    /// `Shift.accentColor(theme:)`). `nil` for every theme except "Colorful"
    /// means "derive from `accent`/`backgroundTint` the usual way" — one
    /// accent color is enough for a theme built around a single hue to feel
    /// coordinated. "Colorful" is different on purpose: it's built around
    /// three CO-EQUAL accents rather than one main accent plus derived
    /// shades, so it sets real, distinct colors here instead.
    var cashOfficeAccentOverride: Color? = nil
    var supervisorAccentOverride: Color? = nil
}

extension AppColorTheme {
    /// High contrast: plain black, white and gray, nothing else. The accent is
    /// the label color itself (black in Light, white in Dark) and the background
    /// is the flat system background.
    static let monochrome = AppColorTheme(
        id: "highContrast", name: "High contrast",
        backgroundTint: Color(.systemBackground),
        accent: Color(.label),
        holidayPay: Color(.systemGray)
    )
}

enum AppColorThemes {
    /// "Green" is the app's original fixed palette; "Blue" was pulled from a
    /// user-supplied wallpaper (a deep navy with a steel/cyan-blue glow,
    /// ~205-215° hue). The rest fill out a spread across the color wheel so
    /// there's a genuinely distinct choice in every direction.
    static let all: [AppColorTheme] = [
        AppColorTheme(
            id: "green", name: "Green",
            backgroundTint: Color(red: 0x00 / 255, green: 0x4E / 255, blue: 0x36 / 255),
            accent: Color(red: 0x31 / 255, green: 0xD1 / 255, blue: 0x58 / 255),
            holidayPay: Color(red: 0x9C / 255, green: 0xAF / 255, blue: 0x88 / 255) // sage
        ),
        AppColorTheme(
            id: "blue", name: "Blue",
            backgroundTint: Color(red: 0x0B / 255, green: 0x2A / 255, blue: 0x4A / 255),
            accent: Color(red: 0x3A / 255, green: 0xA8 / 255, blue: 0xE0 / 255),
            holidayPay: Color(red: 0x86 / 255, green: 0xB2 / 255, blue: 0xA0 / 255) // dusty teal-sage
        ),
        AppColorTheme(
            id: "purple", name: "Purple",
            backgroundTint: Color(red: 0x3B / 255, green: 0x1E / 255, blue: 0x5E / 255),
            accent: Color(red: 0xA8 / 255, green: 0x55 / 255, blue: 0xF7 / 255),
            holidayPay: Color(red: 0x86 / 255, green: 0x90 / 255, blue: 0xB2 / 255) // dusty slate blue
        ),
        AppColorTheme(
            id: "rose", name: "Rose",
            backgroundTint: Color(red: 0x5E / 255, green: 0x1E / 255, blue: 0x3A / 255),
            accent: Color(red: 0xF4 / 255, green: 0x3F / 255, blue: 0x87 / 255),
            holidayPay: Color(red: 0xAC / 255, green: 0x86 / 255, blue: 0xB2 / 255) // dusty mauve
        ),
        AppColorTheme(
            id: "amber", name: "Amber",
            backgroundTint: Color(red: 0x5E / 255, green: 0x35 / 255, blue: 0x10 / 255),
            accent: Color(red: 0xFF / 255, green: 0x9F / 255, blue: 0x1C / 255),
            holidayPay: Color(red: 0xA4 / 255, green: 0xB2 / 255, blue: 0x86 / 255) // muted olive
        ),
        AppColorTheme(
            id: "teal", name: "Teal",
            backgroundTint: Color(red: 0x07 / 255, green: 0x3B / 255, blue: 0x3A / 255),
            accent: Color(red: 0x2D / 255, green: 0xD4 / 255, blue: 0xBF / 255),
            holidayPay: Color(red: 0x86 / 255, green: 0xB2 / 255, blue: 0x8B / 255) // muted sage-green
        ),
        AppColorTheme(
            id: "crimson", name: "Crimson",
            backgroundTint: Color(red: 0x5A / 255, green: 0x14 / 255, blue: 0x20 / 255),
            accent: Color(red: 0xEF / 255, green: 0x44 / 255, blue: 0x44 / 255),
            holidayPay: Color(red: 0xB2 / 255, green: 0xA7 / 255, blue: 0x86 / 255) // muted tan
        ),
        AppColorTheme(
            id: "indigo", name: "Indigo",
            backgroundTint: Color(red: 0x24 / 255, green: 0x1B / 255, blue: 0x5E / 255),
            accent: Color(red: 0x63 / 255, green: 0x66 / 255, blue: 0xF1 / 255),
            holidayPay: Color(red: 0x86 / 255, green: 0xA8 / 255, blue: 0xB2 / 255) // muted steel-cyan
        ),
        // The odd one out on purpose: plain black background (no color tint
        // at all — pure black fading to the system background, per the
        // user's explicit ask) instead of every other theme's
        // deep-saturated-tint-matching-its-accent pattern, AND three
        // co-equal accents (sky blue as the primary/selection accent, pink
        // and lavender as the Cash Office / Supervisor job-badge colors)
        // instead of one accent plus derived shades. All three colors
        // sourced directly from user-supplied swatches.
        AppColorTheme(
            id: "colorful", name: "Colorful",
            backgroundTint: .black,
            accent: Color(red: 0x4F / 255, green: 0xC3 / 255, blue: 0xF7 / 255), // sky blue
            holidayPay: Color(red: 0xB2 / 255, green: 0xA8 / 255, blue: 0x86 / 255), // muted tan
            cashOfficeAccentOverride: Color(red: 0xF0 / 255, green: 0x60 / 255, blue: 0x9E / 255), // pink
            supervisorAccentOverride: Color(red: 0xA6 / 255, green: 0xB1 / 255, blue: 0xE1 / 255) // lavender
        ),
    ]

    static let `default` = all[0]

    static func theme(id: String) -> AppColorTheme {
        all.first { $0.id == id } ?? AppColorThemes.default
    }
}

/// Single source of truth for the active color theme, persisted across
/// launches. Views that need to redraw when it changes hold this as an
/// `@ObservedObject` (matching the existing `BackgroundPulse.shared` pattern)
/// rather than reading a one-shot static value.
@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    private static let storageKey = "selectedColorThemeID"

    /// The theme the user picked. Kept even while high contrast is on, so turning
    /// it off brings their colors back.
    @Published private(set) var selected: AppColorTheme {
        didSet {
            UserDefaults.standard.set(selected.id, forKey: Self.storageKey)
            if selected.id != oldValue.id { AppIconManager.apply(themeID: selected.id) }
        }
    }

    @Published var highContrast: Bool {
        didSet {
            guard highContrast != oldValue else { return }
            FontPreference.store.set(highContrast, forKey: ContrastPreference.key)
            UserDefaults.standard.set(highContrast, forKey: ContrastPreference.key)
            WidgetCenter.shared.reloadAllTimelines()
            BarcodePhoneSync.shared.send(BarcodeStore.value)
        }
    }

    /// What every screen draws with: the picked theme, or the monochrome one.
    var current: AppColorTheme {
        get { highContrast ? .monochrome : selected }
        set { selected = newValue }
    }

    private init() {
        let savedID = UserDefaults.standard.string(forKey: Self.storageKey)
        selected = AppColorThemes.theme(id: savedID ?? AppColorThemes.default.id)
        let enabled = FontPreference.store.bool(forKey: ContrastPreference.key)
            || UserDefaults.standard.bool(forKey: ContrastPreference.key)
        highContrast = enabled
        // `didSet` doesn't run for the first assignment in an initializer; make sure
        // the shared copy (read by widgets and the color helpers) agrees.
        FontPreference.store.set(enabled, forKey: ContrastPreference.key)
    }
}
