import UIKit
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
    /// Distinct tile color for a settings-style glyph, still sitting in this
    /// theme's family. Multi-accent themes (Halloween, Colorful, Rainbow) use
    /// their own extras first so tiles actually show the palette; single-hue
    /// themes get analogous shifts of the accent so neighbouring rows don't
    /// all share the same square.
    func glyphBackground(for symbol: String) -> Color {
        if id == "highContrast" { return Color(.systemGray) }
        let palette = glyphPalette
        return palette[Self.stableSymbolHash(symbol) % palette.count]
    }

    var glyphPalette: [Color] {
        var colors: [Color] = [accent]
        if let cash = cashOfficeAccentOverride { colors.append(cash) }
        if let supervisor = supervisorAccentOverride { colors.append(supervisor) }
        if holidayPay != accent { colors.append(holidayPay) }
        colors.append(contentsOf: analogousAccents)
        return colors
    }

    private var analogousAccents: [Color] {
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        UIColor(accent).getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
        let offsets: [CGFloat] = [32, -32, 58, -58, 86, -86]
        return offsets.map { deg in
            var shifted = hue + deg / 360
            shifted -= floor(shifted)
            let nextSat = min(1, max(0.55, sat * 0.92))
            let nextBri = min(1, max(0.58, bri))
            return Color(hue: Double(shifted), saturation: Double(nextSat), brightness: Double(nextBri))
        }
    }

    private static func stableSymbolHash(_ symbol: String) -> Int {
        var hash: UInt64 = 1469598103934665603
        for byte in symbol.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return Int(hash % UInt64(Int.max))
    }

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

/// A coordinated combination of 3 rainbow colors for the dynamic Rainbow theme:
/// as the user switches tabs, the background gradient and accents smoothly morph
/// to the next triad across the color wheel.
struct RainbowTriad: Equatable {
    let name: String
    let c1: Color
    let c2: Color
    let c3: Color
}

enum AppColorThemes {
    /// Rotating 3-color triads for the Rainbow theme. Each tab switch advances
    /// to the next triad with a smooth fluid animation, morphing the background
    /// gradient into a fresh combination of 3 vibrant colors.
    static let rainbowPalettes: [RainbowTriad] = [
        RainbowTriad(
            name: "Sunset Blaze",
            c1: Color(red: 0.95, green: 0.22, blue: 0.32), // Crimson Rose
            c2: Color(red: 1.00, green: 0.52, blue: 0.12), // Warm Tangerine
            c3: Color(red: 1.00, green: 0.82, blue: 0.16)  // Sun Gold
        ),
        RainbowTriad(
            name: "Citrus Aurora",
            c1: Color(red: 1.00, green: 0.74, blue: 0.12), // Golden Yellow
            c2: Color(red: 0.30, green: 0.86, blue: 0.28), // Electric Lime
            c3: Color(red: 0.05, green: 0.80, blue: 0.65)  // Mint Emerald
        ),
        RainbowTriad(
            name: "Ocean Breeze",
            c1: Color(red: 0.08, green: 0.76, blue: 0.72), // Turquoise Jade
            c2: Color(red: 0.16, green: 0.66, blue: 0.96), // Sky Cyan
            c3: Color(red: 0.26, green: 0.38, blue: 0.94)  // Royal Cobalt
        ),
        RainbowTriad(
            name: "Neon Twilight",
            c1: Color(red: 0.20, green: 0.46, blue: 0.98), // Electric Blue
            c2: Color(red: 0.46, green: 0.28, blue: 0.96), // Royal Indigo
            c3: Color(red: 0.74, green: 0.25, blue: 0.95)  // Vivid Purple
        ),
        RainbowTriad(
            name: "Cosmic Berry",
            c1: Color(red: 0.68, green: 0.24, blue: 0.95), // Electric Violet
            c2: Color(red: 0.98, green: 0.18, blue: 0.60), // Hot Magenta
            c3: Color(red: 1.00, green: 0.36, blue: 0.56)  // Radiant Pink
        ),
        RainbowTriad(
            name: "Prism Flare",
            c1: Color(red: 1.00, green: 0.22, blue: 0.42), // Neon Coral
            c2: Color(red: 1.00, green: 0.52, blue: 0.15), // Blaze Orange
            c3: Color(red: 0.36, green: 0.88, blue: 0.26)  // Vivid Lime
        ),
    ]


    /// "Green" is the app's original fixed palette; "Blue" was pulled from a
    /// user-supplied wallpaper (a deep navy with a steel/cyan-blue glow,
    /// ~205-215° hue). The rest fill out a spread across the color wheel so
    /// there's a genuinely distinct choice in every direction.
    static let all: [AppColorTheme] = [
        // Spooky seasonal Halloween theme: green, pumpkin orange, and witch purple
        // fluid gradients with lightning flashes and climbing spiders easter eggs.
        AppColorTheme(
            id: "halloween", name: "Halloween",
            backgroundTint: Color(red: 0.65, green: 0.18, blue: 0.95), // bright purple
            accent: Color(red: 1.00, green: 0.48, blue: 0.05), // vivid pumpkin orange
            holidayPay: Color(red: 0.42, green: 0.88, blue: 0.16), // crisp apple green
            cashOfficeAccentOverride: Color(red: 0.68, green: 0.20, blue: 0.98), // bright purple
            supervisorAccentOverride: Color(red: 0.42, green: 0.88, blue: 0.16) // apple green
        ),
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
        // Rainbow theme: on every tab change, the background gradient and accents
        // morph into a different combination of 3 colors.
        AppColorTheme(
            id: "rainbow", name: "Rainbow",
            backgroundTint: Color(red: 0.95, green: 0.22, blue: 0.32),
            accent: Color(red: 1.00, green: 0.52, blue: 0.12),
            holidayPay: Color(red: 1.00, green: 0.82, blue: 0.16)
        ),

    ]

    static let `default` = all.first { $0.id == "halloween" } ?? all[0]

    static func theme(id: String) -> AppColorTheme {
        all.first { $0.id == id } ?? AppColorThemes.default
    }
}

/// How the Home calendar itself is drawn. Independent of the color theme:
/// Classic keeps the mixed white header + dark agenda, Light is all white,
/// Dark is all dark. Light Mode and Dark Mode each store their own choice,
/// matching the six-preview Appearance picker.
enum CalendarDisplayStyle: String, CaseIterable, Identifiable {
    case classic
    case light
    case dark

    var id: String { rawValue }

    var name: LocalizedStringKey {
        switch self {
        case .classic: "Classic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Phone chrome in the Settings preview: Classic and Light sit on a light
    /// device, Dark sits on a dark one.
    var usesLightDeviceChrome: Bool { self != .dark }

    /// Agenda list is dark in Classic and Dark, white in Light.
    var agendaIsDark: Bool { self != .light }

    /// Calendar header card is light in Classic and Light, dark in Dark.
    var calendarIsLight: Bool { self != .dark }

    var palette: CalendarDisplayPalette {
        switch self {
        case .classic: .classic
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Concrete colors for one `CalendarDisplayStyle`. Home reads this instead of
/// hard-coded white/black so Classic, Light, and Dark can share one layout.
struct CalendarDisplayPalette {
    let calendarBackground: Color
    let calendarPrimary: Color
    let calendarSecondary: Color
    let calendarMuted: Color
    let selectedColumn: Color
    let selectedWeek: Color
    let divider: Color
    let handle: Color
    let year: Color
    let today: Color
    let outOfMonth: Color
    let agendaBackground: Color
    let agendaPrimary: Color
    let agendaSecondary: Color
    let agendaTertiary: Color
    let agendaWeather: Color
    let emptyStroke: Color
    let stickyHeader: Color
    let demoBannerFill: Color
    let demoBannerText: Color

    static let classic = CalendarDisplayPalette(
        calendarBackground: .white,
        calendarPrimary: Color(red: 0.08, green: 0.08, blue: 0.08),
        calendarSecondary: Color(red: 0.45, green: 0.45, blue: 0.48),
        calendarMuted: Color(red: 0.55, green: 0.55, blue: 0.58),
        selectedColumn: Color(white: 0.94),
        selectedWeek: Color(white: 0.93),
        divider: Color(.systemGray4).opacity(0.8),
        handle: Color(red: 0.52, green: 0.52, blue: 0.54),
        year: Color(red: 0.98, green: 0.15, blue: 0.15),
        today: Color(red: 0.0, green: 0.48, blue: 1.0),
        outOfMonth: Color(red: 0.65, green: 0.70, blue: 0.76),
        agendaBackground: .black,
        agendaPrimary: .white,
        agendaSecondary: Color(white: 0.70),
        agendaTertiary: Color(white: 0.50),
        agendaWeather: Color(white: 0.82),
        emptyStroke: Color(white: 0.25),
        stickyHeader: Color.black.opacity(0.96),
        demoBannerFill: Color(white: 0.16),
        demoBannerText: .white
    )

    static let light = CalendarDisplayPalette(
        calendarBackground: .white,
        calendarPrimary: Color(red: 0.08, green: 0.08, blue: 0.08),
        calendarSecondary: Color(red: 0.45, green: 0.45, blue: 0.48),
        calendarMuted: Color(red: 0.55, green: 0.55, blue: 0.58),
        selectedColumn: Color(white: 0.94),
        selectedWeek: Color(white: 0.93),
        divider: Color(.systemGray4).opacity(0.8),
        handle: Color(red: 0.52, green: 0.52, blue: 0.54),
        year: Color(red: 0.98, green: 0.15, blue: 0.15),
        today: Color(red: 0.0, green: 0.48, blue: 1.0),
        outOfMonth: Color(red: 0.65, green: 0.70, blue: 0.76),
        agendaBackground: .white,
        agendaPrimary: Color(red: 0.08, green: 0.08, blue: 0.08),
        agendaSecondary: Color(red: 0.42, green: 0.42, blue: 0.45),
        agendaTertiary: Color(red: 0.55, green: 0.55, blue: 0.58),
        agendaWeather: Color(red: 0.28, green: 0.28, blue: 0.30),
        emptyStroke: Color(white: 0.78),
        stickyHeader: Color.white.opacity(0.96),
        demoBannerFill: Color(white: 0.94),
        demoBannerText: Color(red: 0.12, green: 0.12, blue: 0.14)
    )

    static let dark = CalendarDisplayPalette(
        calendarBackground: Color(red: 0.11, green: 0.11, blue: 0.12),
        calendarPrimary: Color(white: 0.96),
        calendarSecondary: Color(white: 0.62),
        calendarMuted: Color(white: 0.50),
        selectedColumn: Color(white: 0.20),
        selectedWeek: Color(white: 0.18),
        divider: Color.white.opacity(0.12),
        handle: Color(white: 0.42),
        year: Color(red: 0.98, green: 0.15, blue: 0.15),
        today: Color(red: 0.0, green: 0.52, blue: 1.0),
        outOfMonth: Color(white: 0.38),
        agendaBackground: .black,
        agendaPrimary: .white,
        agendaSecondary: Color(white: 0.70),
        agendaTertiary: Color(white: 0.50),
        agendaWeather: Color(white: 0.82),
        emptyStroke: Color(white: 0.25),
        stickyHeader: Color.black.opacity(0.96),
        demoBannerFill: Color(white: 0.16),
        demoBannerText: .white
    )
}

/// Single source of truth for the active color theme, persisted across
/// launches. Views that need to redraw when it changes hold this as an
/// `@ObservedObject` (matching the existing `BackgroundPulse.shared` pattern)
/// rather than reading a one-shot static value.
@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    private static let lightThemeStorageKey = "selectedLightThemeID"
    private static let darkThemeStorageKey = "selectedDarkThemeID"
    private static let legacyThemeStorageKey = "selectedColorThemeID"
    private static let lightDisplayStorageKey = "lightCalendarDisplayStyle"
    private static let darkDisplayStorageKey = "darkCalendarDisplayStyle"

    private static let lightVibrancyStorageKey = "lightGradientVibrancy"
    private static let darkVibrancyStorageKey = "darkGradientVibrancy"
    private static let legacyVibrancyStorageKey = "gradientVibrancy"
    private static let halloweenDefaultAppliedKey = "halloweenThemeDefaultApplied_v1"

    @Published var activeColorScheme: ColorScheme = .dark

    @Published private(set) var lightTheme: AppColorTheme {
        didSet {
            UserDefaults.standard.set(lightTheme.id, forKey: Self.lightThemeStorageKey)
            UserDefaults.standard.set(lightTheme.id, forKey: Self.legacyThemeStorageKey)
            if activeColorScheme == .light {
                AppIconManager.apply(themeID: lightTheme.id)
            }
        }
    }

    @Published private(set) var darkTheme: AppColorTheme {
        didSet {
            UserDefaults.standard.set(darkTheme.id, forKey: Self.darkThemeStorageKey)
            UserDefaults.standard.set(darkTheme.id, forKey: Self.legacyThemeStorageKey)
            if activeColorScheme == .dark {
                AppIconManager.apply(themeID: darkTheme.id)
            }
        }
    }

    @Published var lightGradientVibrancy: Double {
        didSet {
            UserDefaults.standard.set(lightGradientVibrancy, forKey: Self.lightVibrancyStorageKey)
            UserDefaults.standard.set(lightGradientVibrancy, forKey: Self.legacyVibrancyStorageKey)
        }
    }

    @Published var darkGradientVibrancy: Double {
        didSet {
            UserDefaults.standard.set(darkGradientVibrancy, forKey: Self.darkVibrancyStorageKey)
            UserDefaults.standard.set(darkGradientVibrancy, forKey: Self.legacyVibrancyStorageKey)
        }
    }

    @Published var highContrast: Bool {
        didSet {
            guard highContrast != oldValue else { return }
            FontPreference.store.set(highContrast, forKey: ContrastPreference.key)
            UserDefaults.standard.set(highContrast, forKey: ContrastPreference.key)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    @Published var lightDisplayStyle: CalendarDisplayStyle {
        didSet { UserDefaults.standard.set(lightDisplayStyle.rawValue, forKey: Self.lightDisplayStorageKey) }
    }

    @Published var darkDisplayStyle: CalendarDisplayStyle {
        didSet { UserDefaults.standard.set(darkDisplayStyle.rawValue, forKey: Self.darkDisplayStorageKey) }
    }

    /// The active 3-color palette combination index for Rainbow theme.
    @Published var rainbowComboIndex: Int = 0

    /// Advances to the next 3-color combination when the active tab changes.
    func advanceRainbowCombo() {
        guard lightTheme.id == "rainbow" || darkTheme.id == "rainbow" else { return }
        withAnimation(.easeInOut(duration: 1.4)) {
            rainbowComboIndex = (rainbowComboIndex + 1) % AppColorThemes.rainbowPalettes.count
        }
    }

    func displayStyle(for scheme: ColorScheme) -> CalendarDisplayStyle {
        scheme == .light ? lightDisplayStyle : darkDisplayStyle
    }

    func setDisplayStyle(_ style: CalendarDisplayStyle, for scheme: ColorScheme) {
        if scheme == .light {
            lightDisplayStyle = style
        } else {
            darkDisplayStyle = style
        }
    }

    var currentDisplayStyle: CalendarDisplayStyle {
        displayStyle(for: activeColorScheme)
    }

    var currentChrome: CalendarDisplayPalette {
        currentDisplayStyle.palette
    }

    func selectedTheme(for scheme: ColorScheme) -> AppColorTheme {
        scheme == .light ? lightTheme : darkTheme
    }

    func setSelectedTheme(_ theme: AppColorTheme, for scheme: ColorScheme) {
        if scheme == .light {
            lightTheme = theme
        } else {
            darkTheme = theme
        }
        AppIconManager.apply(themeID: theme.id)
    }

    func vibrancy(for scheme: ColorScheme) -> Double {
        scheme == .light ? lightGradientVibrancy : darkGradientVibrancy
    }

    func setVibrancy(_ value: Double, for scheme: ColorScheme) {
        let clamped = max(0.0, min(1.0, value))
        if scheme == .light {
            lightGradientVibrancy = clamped
        } else {
            darkGradientVibrancy = clamped
        }
    }

    func overlayOpacity(for scheme: ColorScheme) -> Double {
        let v = vibrancy(for: scheme)
        return (1.0 - v) * 0.90
    }

    func current(for scheme: ColorScheme) -> AppColorTheme {
        if highContrast { return .monochrome }
        let base = selectedTheme(for: scheme)
        if base.id == "rainbow" {
            let triad = AppColorThemes.rainbowPalettes[rainbowComboIndex % AppColorThemes.rainbowPalettes.count]
            return AppColorTheme(
                id: "rainbow",
                name: "Rainbow",
                backgroundTint: triad.c1,
                accent: triad.c2,
                holidayPay: triad.c3,
                cashOfficeAccentOverride: triad.c2,
                supervisorAccentOverride: triad.c3
            )
        }
        return base
    }

    /// What every screen draws with: the picked theme, the dynamic rainbow combination, or monochrome.
    var current: AppColorTheme {
        get { current(for: activeColorScheme) }
        set { setSelectedTheme(newValue, for: activeColorScheme) }
    }

    var selected: AppColorTheme {
        selectedTheme(for: activeColorScheme)
    }

    var gradientVibrancy: Double {
        get { vibrancy(for: activeColorScheme) }
        set { setVibrancy(newValue, for: activeColorScheme) }
    }

    var backgroundOverlayOpacity: Double {
        overlayOpacity(for: activeColorScheme)
    }

    func updateActiveColorScheme(_ scheme: ColorScheme) {
        guard activeColorScheme != scheme else { return }
        activeColorScheme = scheme
        AppIconManager.apply(themeID: current.id)
    }

    private init() {
        // Automatically default to Halloween once upon updating the app.
        if !UserDefaults.standard.bool(forKey: Self.halloweenDefaultAppliedKey) {
            UserDefaults.standard.set(true, forKey: Self.halloweenDefaultAppliedKey)
            UserDefaults.standard.set("halloween", forKey: Self.lightThemeStorageKey)
            UserDefaults.standard.set("halloween", forKey: Self.darkThemeStorageKey)
            UserDefaults.standard.set("halloween", forKey: Self.legacyThemeStorageKey)
        }

        let legacyID = UserDefaults.standard.string(forKey: Self.legacyThemeStorageKey)
        let lightSavedID = UserDefaults.standard.string(forKey: Self.lightThemeStorageKey) ?? legacyID
        let darkSavedID = UserDefaults.standard.string(forKey: Self.darkThemeStorageKey) ?? legacyID

        lightTheme = AppColorThemes.theme(id: lightSavedID ?? AppColorThemes.default.id)
        darkTheme = AppColorThemes.theme(id: darkSavedID ?? AppColorThemes.default.id)

        lightDisplayStyle = CalendarDisplayStyle(
            rawValue: UserDefaults.standard.string(forKey: Self.lightDisplayStorageKey) ?? ""
        ) ?? .classic
        darkDisplayStyle = CalendarDisplayStyle(
            rawValue: UserDefaults.standard.string(forKey: Self.darkDisplayStorageKey) ?? ""
        ) ?? .classic

        let legacyVibrancy = UserDefaults.standard.object(forKey: Self.legacyVibrancyStorageKey) != nil
            ? UserDefaults.standard.double(forKey: Self.legacyVibrancyStorageKey)
            : 1.0

        if UserDefaults.standard.object(forKey: Self.lightVibrancyStorageKey) != nil {
            lightGradientVibrancy = max(0.0, min(1.0, UserDefaults.standard.double(forKey: Self.lightVibrancyStorageKey)))
        } else {
            lightGradientVibrancy = legacyVibrancy
        }

        if UserDefaults.standard.object(forKey: Self.darkVibrancyStorageKey) != nil {
            darkGradientVibrancy = max(0.0, min(1.0, UserDefaults.standard.double(forKey: Self.darkVibrancyStorageKey)))
        } else {
            darkGradientVibrancy = legacyVibrancy
        }

        let style = UITraitCollection.current.userInterfaceStyle
        activeColorScheme = (style == .light ? .light : .dark)

        let enabled = FontPreference.store.bool(forKey: ContrastPreference.key)
            || UserDefaults.standard.bool(forKey: ContrastPreference.key)
        highContrast = enabled
        FontPreference.store.set(enabled, forKey: ContrastPreference.key)

        Task { @MainActor in
            AppIconManager.apply(themeID: self.current.id)
        }
    }
}
