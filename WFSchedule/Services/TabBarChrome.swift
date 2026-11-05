import SwiftUI
import UIKit

/// Keeps the system tab bar readable on the all-white Light calendar.
/// Liquid-glass otherwise paints unselected items as a pale gray that vanishes
/// on white agenda content.
enum TabBarChrome {
    @MainActor
    static func apply(accent: Color, lightSurface: Bool) {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        let tabBar = UITabBar.appearance()
        if lightSurface {
            let muted = UIColor(white: 0.26, alpha: 1)
            let selected = Self.darkReadable(UIColor(accent), against: .white)
            for layout in [
                appearance.stackedLayoutAppearance,
                appearance.inlineLayoutAppearance,
                appearance.compactInlineLayoutAppearance
            ] {
                layout.normal.iconColor = muted
                layout.normal.titleTextAttributes = [.foregroundColor: muted]
                layout.selected.iconColor = selected
                layout.selected.titleTextAttributes = [.foregroundColor: selected]
            }
            tabBar.unselectedItemTintColor = muted
            tabBar.tintColor = selected
        } else {
            tabBar.unselectedItemTintColor = nil
            tabBar.tintColor = nil
        }

        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        Self.refreshVisibleTabBars(with: appearance, lightSurface: lightSurface, accent: accent)
    }

    @MainActor
    private static func refreshVisibleTabBars(with appearance: UITabBarAppearance, lightSurface: Bool, accent: Color) {
        let muted = UIColor(white: 0.26, alpha: 1)
        let selected = Self.darkReadable(UIColor(accent), against: .white)
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                for tabBar in Self.tabBars(in: window) {
                    tabBar.standardAppearance = appearance
                    tabBar.scrollEdgeAppearance = appearance
                    if lightSurface {
                        tabBar.unselectedItemTintColor = muted
                        tabBar.tintColor = selected
                    } else {
                        tabBar.unselectedItemTintColor = nil
                        tabBar.tintColor = nil
                    }
                }
            }
        }
    }

    @MainActor
    private static func tabBars(in view: UIView) -> [UITabBar] {
        var found: [UITabBar] = []
        if let tabBar = view as? UITabBar { found.append(tabBar) }
        for child in view.subviews {
            found.append(contentsOf: tabBars(in: child))
        }
        return found
    }

    /// Darkens `color` toward black until it clears ~4.5:1 on `background`.
    private static func darkReadable(_ color: UIColor, against background: UIColor) -> UIColor {
        func luminance(_ c: UIColor) -> CGFloat {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            func lin(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        }
        func contrast(_ a: UIColor, _ b: UIColor) -> CGFloat {
            let la = luminance(a), lb = luminance(b)
            return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
        }
        if contrast(color, background) >= 4.5 { return color }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        var t: CGFloat = 0
        var result = color
        while t < 1, contrast(result, background) < 4.5 {
            t += 0.05
            result = UIColor(red: r * (1 - t), green: g * (1 - t), blue: b * (1 - t), alpha: 1)
        }
        return result
    }
}
