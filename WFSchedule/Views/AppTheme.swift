import SwiftUI
import UIKit

/// Drives the slow, organic fluid gradient morphing for every `AppBackground` on
/// screen from a single shared, synchronized driver. Two incommensurate animation
/// cycles (11s and 17s) produce non-repeating Lissajous drift paths for the color
/// orbs, recreating the hypnotic liquid-glow aesthetic of Apple Music lyrics
/// without running per-screen timers or taxing the battery.
@MainActor
private final class BackgroundMorphDriver: ObservableObject {
    static let shared = BackgroundMorphDriver()

    @Published var phase1 = false
    @Published var phase2 = false

    private init() {
        Task { @MainActor in
            self.updateAnimation()
        }
        // Stands down for Reduce Motion and Low Power Mode, resuming when turned off.
        let center = NotificationCenter.default
        for name in [
            UIAccessibility.reduceMotionStatusDidChangeNotification,
            Notification.Name.NSProcessInfoPowerStateDidChange
        ] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateAnimation() }
            }
        }
    }

    private func updateAnimation() {
        let shouldAnimate = !UIAccessibility.isReduceMotionEnabled && !ProcessInfo.processInfo.isLowPowerModeEnabled
        if shouldAnimate {
            withAnimation(.easeInOut(duration: 11.0).repeatForever(autoreverses: true)) {
                phase1 = true
            }
            withAnimation(.easeInOut(duration: 17.0).repeatForever(autoreverses: true)) {
                phase2 = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.3)) {
                phase1 = false
                phase2 = false
            }
        }
    }
}

/// An Apple Music-inspired fluid animated background: multiple organic color orbs
/// drift, breathe, scale, and gently rotate across the screen under a deep Gaussian
/// blur, slowly morphing into dynamic liquid color gradients.
/// Seamlessly fills and adapts to the full screen edge-to-edge across all views,
/// ensuring the background smoothly continues without cutoffs or color jumps.
struct AppBackground: View {
    var baseOpacity: Double = 0.46

    @ObservedObject private var morph = BackgroundMorphDriver.shared
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var activeTheme: AppColorTheme {
        theme.current(for: colorScheme)
    }

    /// Strength eases back in Light mode or high contrast / reduced transparency
    /// so text contrast remains compliant and crisp.
    private var strength: Double {
        if contrast == .increased || reduceTransparency { return 0.25 }
        let lightBase = 0.70 + 0.30 * theme.vibrancy(for: colorScheme)
        return colorScheme == .light ? lightBase : 1.0
    }

    private var effectiveOpacity: Double {
        let base = baseOpacity * strength
        let pulseFactor = morph.phase1 ? 0.04 : -0.04
        return max(0.05, base + pulseFactor * strength)
    }

    var body: some View {
        if theme.highContrast {
            Color(.systemBackground).ignoresSafeArea()
        } else {
            ZStack {
                Color(.systemBackground)

                GeometryReader { proxy in
                    let w = proxy.size.width
                    let h = proxy.size.height

                    ZStack {
                        // Orb 1: Primary deep theme aura (Top-Leading)
                        Ellipse()
                            .fill(orb1Color)
                            .frame(width: w * 1.35, height: h * 0.55)
                            .position(
                                x: morph.phase1 ? w * 0.22 : w * 0.38,
                                y: morph.phase2 ? h * 0.20 : h * 0.12
                            )
                            .scaleEffect(morph.phase1 ? 1.15 : 0.94)
                            .rotationEffect(.degrees(morph.phase2 ? 22 : -18))

                        // Orb 2: Luminous accent highlight (Top-Trailing)
                        Ellipse()
                            .fill(orb2Color)
                            .frame(width: w * 1.20, height: h * 0.50)
                            .position(
                                x: morph.phase2 ? w * 0.68 : w * 0.84,
                                y: morph.phase1 ? h * 0.32 : h * 0.22
                            )
                            .scaleEffect(morph.phase2 ? 0.92 : 1.16)
                            .rotationEffect(.degrees(morph.phase1 ? -28 : 24))

                        // Orb 3: Harmonious secondary glow (Center-Leading)
                        RoundedRectangle(cornerRadius: w * 0.45)
                            .fill(orb3Color)
                            .frame(width: w * 1.25, height: h * 0.52)
                            .position(
                                x: morph.phase1 ? w * 0.35 : w * 0.18,
                                y: morph.phase2 ? h * 0.54 : h * 0.44
                            )
                            .scaleEffect(morph.phase1 ? 1.12 : 0.88)
                            .rotationEffect(.degrees(morph.phase2 ? 28 : -22))

                        // Orb 4: Ambient floating pool (Lower-Trailing)
                        Ellipse()
                            .fill(orb4Color)
                            .frame(width: w * 1.20, height: h * 0.52)
                            .position(
                                x: morph.phase2 ? w * 0.62 : w * 0.80,
                                y: morph.phase1 ? h * 0.72 : h * 0.62
                            )
                            .scaleEffect(morph.phase2 ? 1.16 : 0.94)
                            .rotationEffect(.degrees(morph.phase1 ? 22 : -30))

                        // Orb 5: Deep base tone filling the lower screen (Bottom-Leading / Center)
                        Ellipse()
                            .fill(orb1Color)
                            .frame(width: w * 1.35, height: h * 0.55)
                            .position(
                                x: morph.phase1 ? w * 0.30 : w * 0.48,
                                y: morph.phase2 ? h * 0.88 : h * 0.80
                            )
                            .scaleEffect(morph.phase1 ? 1.14 : 0.92)
                            .rotationEffect(.degrees(morph.phase2 ? -18 : 20))
                    }
                    .blur(radius: 80)
                }
                .ignoresSafeArea()

                // White/black accessibility overlay controlled by the settings bar adjuster.
                // At 100% full: 0 overlay (super colorful).
                // At 0% full: 90% overlay (gradient minimal 10% visibility).
                Color(colorScheme == .dark ? .black : .white)
                    .opacity(theme.overlayOpacity(for: colorScheme))
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    private var orb1Color: Color {
        activeTheme.backgroundTint.opacity(effectiveOpacity * 0.95)
    }

    private var orb2Color: Color {
        if activeTheme.id == "rainbow" {
            return activeTheme.accent.opacity(effectiveOpacity * 0.85)
        }
        if let custom = activeTheme.cashOfficeAccentOverride {
            return custom.opacity(effectiveOpacity * 0.75)
        }
        return activeTheme.accent.opacity(effectiveOpacity * 0.65)
    }

    private var orb3Color: Color {
        if activeTheme.id == "rainbow" {
            return activeTheme.holidayPay.opacity(effectiveOpacity * 0.85)
        }
        if let custom = activeTheme.supervisorAccentOverride {
            return custom.opacity(effectiveOpacity * 0.75)
        }
        return activeTheme.holidayPay.opacity(effectiveOpacity * 0.75)
    }

    private var orb4Color: Color {
        if activeTheme.id == "rainbow" {
            return activeTheme.accent.opacity(effectiveOpacity * 0.80)
        }
        if activeTheme.id == "colorful" {
            return activeTheme.accent.opacity(effectiveOpacity * 0.65)
        }
        return activeTheme.backgroundTint
            .mixed(with: activeTheme.accent, amount: 0.4)
            .opacity(effectiveOpacity * 0.70)
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

    private static var accentColorCache: [String: Color] = [:]
    private static let cacheLock = NSLock()

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
        let isHigh = ContrastPreference.high
        let cacheKey = "\(job)_\(theme.id)_\(isHigh)"

        cacheLock.lock()
        if let cached = accentColorCache[cacheKey] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let color: Color
        if isHigh {
            color = job == "Supervisor" ? Color(.label) : Color(.systemGray)
        } else {
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
            color = Color.readable(base, minimumContrast: 3)
        }

        cacheLock.lock()
        accentColorCache[cacheKey] = color
        cacheLock.unlock()

        return color
    }

    func accentColor(theme: AppColorTheme) -> Color {
        Self.accentColor(forJob: job, theme: theme)
    }
}
