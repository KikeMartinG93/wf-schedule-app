import SwiftUI
import UIKit

/// Drives the "breathing" pulse for every `AppBackground` on screen from a
/// single shared, always-in-sync animation instead of each screen's own
/// `@State` starting its own infinite `repeatForever` loop. SwiftUI's
/// `TabView` keeps every tab's view alive, so with a per-instance animation
/// the app was running one independent infinite animation timeline per tab
/// (5+) at all times, even for backgrounded tabs — pure battery/CPU waste for
/// a purely decorative effect. One shared driver looks identical (all
/// backgrounds already pulsed in lockstep) and costs a fraction as much.
@MainActor
private final class BackgroundPulse: ObservableObject {
    static let shared = BackgroundPulse()

    @Published var breatheIn = false

    private init() {
        updateAnimation()
        // The pulse is purely decorative, so it stands down for Reduce Motion and
        // Low Power Mode (a forever-running animation is a steady battery cost)
        // and comes back if either is switched off.
        let center = NotificationCenter.default
        for name in [UIAccessibility.reduceMotionStatusDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateAnimation() }
            }
        }
    }

    private func updateAnimation() {
        let shouldAnimate = !UIAccessibility.isReduceMotionEnabled && !ProcessInfo.processInfo.isLowPowerModeEnabled
        if shouldAnimate {
            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) { breatheIn = true }
        } else {
            // A new, non-repeating animation replaces the endless one.
            withAnimation(.easeOut(duration: 0.3)) { breatheIn = false }
        }
    }
}

/// The green background gradient used on every screen, with a slow "breathing"
/// pulse — the tint's opacity drifts up and down on a long, gentle cycle rather
/// than sitting static. `baseOpacity` preserves each screen's own tuned
/// intensity; the pulse moves symmetrically around it.
struct AppBackground: View {
    var baseOpacity: Double = 0.42
    private let amplitude: Double = 0.08

    @ObservedObject private var pulse = BackgroundPulse.shared
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Secondary text (weekday letters, captions) sits directly on this gradient,
    /// so its strength is what limits their contrast. In Light mode the full tint
    /// pushes secondary labels toward ~3:1, so it's eased back; Increase Contrast
    /// and Reduce Transparency get a nearly flat background.
    private var strength: Double {
        if contrast == .increased || reduceTransparency { return 0.25 }
        return colorScheme == .light ? 0.65 : 1
    }

    var body: some View {
        if theme.highContrast {
            Color(.systemBackground).ignoresSafeArea()
        } else {
            gradient
        }
    }

    private var gradient: some View {
        let base = baseOpacity * strength
        return LinearGradient(
            colors: [
                theme.current.backgroundTint.opacity(pulse.breatheIn ? base + amplitude * strength : base - amplitude * strength),
                Color(.systemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

private extension Color {
    /// Linear-interpolates toward `other` in RGB space. Used to derive
    /// Supervisor/Cash Office's job badge colors FROM the active color theme
    /// instead of a fixed pair of hardcoded greens, so they retint along with
    /// everything else instead of being the one thing left behind.
    func mixed(with other: Color, amount: Double) -> Color {
        let ui1 = UIColor(self)
        let ui2 = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        ui1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        ui2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(amount)
        return Color(
            red: Double(r1 + (r2 - r1) * t),
            green: Double(g1 + (g2 - g1) * t),
            blue: Double(b1 + (b2 - b1) * t)
        )
    }
}

extension Shift {
    /// Job colors for everything besides Supervisor/Cash Office. Derived from
    /// the active theme's accent as an analogous palette (the same saturation
    /// and brightness, hue nudged a little either way) so every color on screen
    /// sits in one family instead of a fixed rainbow. "Colorful" is the
    /// exception on purpose: its three co-equal accents are the palette.
    private static func jobPalette(for theme: AppColorTheme) -> [Color] {
        if let cash = theme.cashOfficeAccentOverride, let supervisor = theme.supervisorAccentOverride {
            return [theme.accent, cash, supervisor]
        }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        UIColor(theme.accent).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let offsets: [CGFloat] = [-40, -25, -12, 12, 25, 40, 55]
        return offsets.enumerated().map { index, degrees in
            var shifted = hue + degrees / 360
            shifted -= floor(shifted)
            let sat = min(1, max(0.45, saturation - (index.isMultiple(of: 2) ? 0.08 : 0)))
            let bri = min(1, max(0.7, brightness - (index.isMultiple(of: 2) ? 0 : 0.1)))
            return Color(hue: Double(shifted), saturation: Double(sat), brightness: Double(bri))
        }
    }

    /// Swift's `String.hashValue` is randomized per process launch (a security
    /// feature against hash-flooding) — using it here would mean the same job
    /// gets a different badge color every time the app restarts. This is a
    /// fixed, deterministic hash instead, so the mapping is actually stable
    /// across launches like the palette below assumes.
    private static func stableHash(_ s: String) -> Int {
        var hash: UInt64 = 1469598103934665603 // FNV-1a offset basis
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211 // FNV-1a prime
        }
        return Int(hash % UInt64(Int.max))
    }

    /// Supervisor and Cash Office get colors DERIVED from the active theme
    /// (a deep theme-tinted shade for Supervisor, the theme's accent itself
    /// for Cash Office — the same relationship those two fixed greens had to
    /// each other in the original palette) so they never clash with whichever
    /// color theme is selected; other jobs get a stable color from that
    /// theme's analogous palette (see `jobPalette`), hashed off the job name so
    /// the same job always lands on the same color within a theme.
    ///
    /// Standalone (not just an instance method) so the Home calendar's legend
    /// can show what "Supervisor"/"Cash Office" look like without needing an
    /// actual `Shift` to ask.
    static func accentColor(forJob job: String, theme: AppColorTheme) -> Color {
        // These color dots, bars and legend swatches — graphics that carry
        // meaning — so each is nudged to at least 3:1 against the surface
        // it's drawn on (Apple's / WCAG's bar for non-text elements).
        // High contrast: no hue. Supervisor is solid black/white, everything
        // else a mid gray, so the two kinds of work still read apart.
        if ContrastPreference.high {
            return job == "Supervisor" ? Color(.label) : Color(.systemGray)
        }
        let base: Color
        switch job {
        case "Supervisor":
            base = theme.supervisorAccentOverride ?? theme.backgroundTint.mixed(with: theme.accent, amount: 0.35)
        case "Cash Office":
            base = theme.cashOfficeAccentOverride ?? theme.accent
        default:
            let palette = jobPalette(for: theme)
            base = palette[Self.stableHash(job) % palette.count]
        }
        return Color.readable(base, minimumContrast: 3)
    }

    func accentColor(theme: AppColorTheme) -> Color {
        Self.accentColor(forJob: job, theme: theme)
    }
}
