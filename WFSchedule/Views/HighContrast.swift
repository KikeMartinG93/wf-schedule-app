import SwiftUI
import UIKit

/// In-app high contrast switch. It overrides the window's Increase Contrast
/// trait, so everything that already responds to the system setting responds to
/// this too: system colors and materials, the app's own contrast-adjusted
/// colors (7:1 text), and the flat background. The system Increase Contrast
/// setting keeps working on its own.
enum HighContrast {
    static let key = "highContrastEnabled"
}

struct HighContrastApplier: UIViewRepresentable {
    let enabled: Bool

    func makeUIView(context: Context) -> ApplierView {
        let view = ApplierView()
        view.isUserInteractionEnabled = false
        view.enabled = enabled
        return view
    }

    func updateUIView(_ view: ApplierView, context: Context) {
        view.enabled = enabled
        view.apply()
    }

    final class ApplierView: UIView {
        var enabled = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        func apply() {
            guard let window else { return }
            if enabled {
                window.traitOverrides.accessibilityContrast = .high
            } else {
                window.traitOverrides.remove(UITraitAccessibilityContrast.self)
            }
        }
    }
}

/// Glass cards are near-white on white in high contrast, so they get a thin
/// outline to keep their edges visible. Observes the theme itself so it
/// updates the moment the setting changes.
private struct HighContrastOutline: ViewModifier {
    let cornerRadius: CGFloat
    @ObservedObject private var theme = ThemeManager.shared

    func body(content: Content) -> some View {
        content.overlay {
            if theme.highContrast {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.45), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func highContrastOutline(cornerRadius: CGFloat = 24) -> some View {
        modifier(HighContrastOutline(cornerRadius: cornerRadius))
    }
}
