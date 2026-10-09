import CoreGraphics
import Foundation

/// Renders a Code 39 ("Code 3 of 9") barcode as a `CGImage`. Standard 43-character
/// symbology (0-9, A-Z, seven symbols, plus the `*` start/stop character) — each
/// character is 9 alternating bar/space elements, 3 of which are "wide."
///
/// A real barcode scanner needs precise, physically-sized bar widths — this is
/// meant for on-screen display (Settings preview, the Watch app's full-screen
/// view), not guaranteed to scan reliably when shrunk into a watch complication.
enum Code39Barcode {
    /// `true` = wide element, `false` = narrow. 9 elements per character,
    /// alternating bar/space starting and ending on a bar (5 bars + 4 spaces).
    private static let patterns: [Character: [Bool]] = [
        "0": [false, false, false, true, true, false, true, false, false],
        "1": [true, false, false, true, false, false, false, false, true],
        "2": [false, false, true, true, false, false, false, false, true],
        "3": [true, false, true, true, false, false, false, false, false],
        "4": [false, false, false, true, true, false, false, false, true],
        "5": [true, false, false, true, true, false, false, false, false],
        "6": [false, false, true, true, true, false, false, false, false],
        "7": [false, false, false, true, false, false, true, false, true],
        "8": [true, false, false, true, false, false, true, false, false],
        "9": [false, false, true, true, false, false, true, false, false],
        "A": [true, false, false, false, false, true, false, false, true],
        "B": [false, false, true, false, false, true, false, false, true],
        "C": [true, false, true, false, false, true, false, false, false],
        "D": [false, false, false, false, true, true, false, false, true],
        "E": [true, false, false, false, true, true, false, false, false],
        "F": [false, false, true, false, true, true, false, false, false],
        "G": [false, false, false, false, false, true, true, false, true],
        "H": [true, false, false, false, false, true, true, false, false],
        "I": [false, false, true, false, false, true, true, false, false],
        "J": [false, false, false, false, true, true, true, false, false],
        "K": [true, false, false, false, false, false, false, true, true],
        "L": [false, false, true, false, false, false, false, true, true],
        "M": [true, false, true, false, false, false, false, true, false],
        "N": [false, false, false, false, true, false, false, true, true],
        "O": [true, false, false, false, true, false, false, true, false],
        "P": [false, false, true, false, true, false, false, true, false],
        "Q": [false, false, false, false, false, false, true, true, true],
        "R": [true, false, false, false, false, false, true, true, false],
        "S": [false, false, true, false, false, false, true, true, false],
        "T": [false, false, false, false, true, false, true, true, false],
        "U": [true, true, false, false, false, false, false, false, true],
        "V": [false, true, true, false, false, false, false, false, true],
        "W": [true, true, true, false, false, false, false, false, false],
        "X": [false, true, false, false, true, false, false, false, true],
        "Y": [true, true, false, false, true, false, false, false, false],
        "Z": [false, true, true, false, true, false, false, false, false],
        "-": [false, true, false, false, false, false, true, false, true],
        ".": [true, true, false, false, false, false, true, false, false],
        " ": [false, true, true, false, false, false, true, false, false],
        "$": [false, true, false, true, false, true, false, false, false],
        "/": [false, true, false, true, false, false, false, true, false],
        "+": [false, true, false, false, false, true, false, true, false],
        "%": [false, false, false, true, false, true, false, true, false],
        "*": [false, true, false, true, true, false, true, false, false],
    ]

    // Narrow element = 1 unit, wide = 3 units (the standard Code 39 ratio),
    // plus a 1-unit narrow gap between characters. 8px narrow (not something
    // tiny like 2px) is resolution headroom — at 2px a narrow bar's rounded
    // corners have almost no pixels to work with, so scaling the result up
    // (every display site does, via a wider on-screen frame) turned smooth
    // curves into visible stair-stepping. This is purely resolution, not
    // proportion — the 1:3 ratio is unchanged regardless of this constant.
    private static let narrow = 8
    private static let wide = narrow * 3
    private static let quietZone = narrow * 10

    private static func normalized(_ code: String) -> String? {
        let cleaned = code.uppercased().filter { patterns[$0] != nil }
        guard !cleaned.isEmpty else { return nil }
        return "*\(cleaned)*"
    }

    /// Total pixel width the barcode will render at — fixed by content
    /// alone, independent of whatever height it's drawn at.
    private static func contentWidth(for full: String) -> Int {
        var totalWidth = quietZone * 2
        for char in full {
            guard let pattern = patterns[char] else { continue }
            totalWidth += pattern.reduce(0) { $0 + ($1 ? wide : narrow) }
            totalWidth += narrow // inter-character gap
        }
        return totalWidth
    }

    /// `code` should be the raw barcode digits/characters only (no `*` — those
    /// are added automatically as the required start/stop character).
    /// `roundedBars` controls whether each individual bar has pill-shaped
    /// rounded ends (Settings preview, the Watch app's full-screen view) or
    /// plain square edges (the complication, which conceals the OVERALL
    /// image's corners with its own rounded-frame clip shape instead — round
    /// both and the two roundings compound into a busier, less finished look
    /// at that size).
    static func cgImage(for code: String, height: Int = 200, roundedBars: Bool = true) -> CGImage? {
        guard let full = normalized(code) else { return nil }
        let totalWidth = contentWidth(for: full)

        guard let context = CGContext(
            data: nil,
            width: totalWidth,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: totalWidth, height: height))
        context.setFillColor(gray: 0, alpha: 1)

        var x = quietZone
        for char in full {
            guard let pattern = patterns[char] else { continue }
            for (index, isWide) in pattern.enumerated() {
                let elementWidth = isWide ? wide : narrow
                let isBar = index % 2 == 0
                if isBar {
                    let rect = CGRect(x: x, y: 0, width: elementWidth, height: height)
                    if roundedBars {
                        // Each bar's own half-width as the radius: a narrow
                        // bar comes out as a full pill/capsule, a wide bar
                        // gets rounded corners scaled to match, so the look
                        // stays consistent across both element widths
                        // instead of one looking barely-rounded next to a
                        // fully pill-shaped other.
                        let cornerRadius = CGFloat(elementWidth) / 2
                        let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
                        context.addPath(path)
                        context.fillPath()
                    } else {
                        context.fill(rect)
                    }
                }
                x += elementWidth
            }
            x += narrow
        }

        return context.makeImage()
    }
}
