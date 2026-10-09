import SwiftUI
import UIKit

/// WCAG-style contrast helpers. The theme accents are bright, saturated colors
/// picked to look good as fills; used raw as text or thin graphics on a light
/// background several of them (green, amber, teal, sky blue) come out around
/// 2:1, well under Apple's recommended 4.5:1 for text and 3:1 for meaningful
/// graphics. These derive a variant of any color that clears the bar in the
/// current appearance (light / dark, and a stricter 7:1 under Increase Contrast)
/// while keeping its hue.
private extension UIColor {
    var luminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    func contrast(with other: UIColor) -> CGFloat {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    func mixed(toward target: UIColor, by t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        target.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: 1)
    }

    /// Nudges toward white or black (whichever is farther from `background`)
    /// until it reaches `target` contrast against it. Already-passing colors are untouched.
    func meeting(contrast target: CGFloat, against background: UIColor) -> UIColor {
        if contrast(with: background) >= target { return self }
        let pole: UIColor = background.luminance > 0.4 ? .black : .white
        var t: CGFloat = 0
        var result = self
        while t < 1, result.contrast(with: background) < target {
            t += 0.04
            result = mixed(toward: pole, by: min(t, 1))
        }
        return result
    }
}

extension Color {
    /// `base`, adjusted per appearance so it reads on the app's backgrounds.
    /// 4.5:1 suits text; pass 3 for dots, bars and other graphics.
    static func readable(_ base: Color, minimumContrast: CGFloat = 4.5) -> Color {
        Color(uiColor: UIColor { traits in
            let strict = traits.accessibilityContrast == .high
            // Worst-case surfaces the app draws on: grouped light gray / elevated dark gray.
            let background: UIColor = traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.14, alpha: 1)
                : UIColor(white: 0.95, alpha: 1)
            let target = strict ? max(minimumContrast, 7) : minimumContrast
            return UIColor(base).resolvedColor(with: traits).meeting(contrast: target, against: background)
        })
    }

    /// A fill for prominent buttons: `base` darkened just enough that white
    /// label text on it reaches 4.5:1 (7:1 with Increase Contrast).
    static func buttonFill(_ base: Color) -> Color {
        // High contrast: black buttons in Light, dark gray in Dark (so they still
        // show against a black background), both with white text.
        if ContrastPreference.high {
            return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.32, alpha: 1) : .black })
        }
        return Color(uiColor: UIColor { traits in
            let target: CGFloat = traits.accessibilityContrast == .high ? 7 : 4.5
            return UIColor(base).resolvedColor(with: traits).meeting(contrast: target, against: .white)
        })
    }

    /// Black or white — whichever reads better on a solid `fill`.
    static func onFill(_ fill: Color) -> Color {
        Color(uiColor: UIColor { traits in
            let resolved = UIColor(fill).resolvedColor(with: traits)
            return resolved.contrast(with: .white) >= resolved.contrast(with: .black) ? .white : .black
        })
    }
}

extension AppColorTheme {
    /// Accent for text and tinted controls (links, borderless buttons, symbols).
    var readableAccent: Color { .readable(accent) }
    /// Switch track color. In high contrast the accent is plain white in Dark, and a
    /// white track with a white knob has no visible knob, so use mid gray there.
    var toggleTint: Color {
        guard ContrastPreference.high else { return readableAccent }
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.5, alpha: 1) : .black })
    }
    /// Accent for solid button backgrounds that carry white text.
    var buttonFill: Color { .buttonFill(accent) }
}
