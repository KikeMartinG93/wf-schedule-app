import CoreGraphics
import Foundation
import SwiftUI

/// Minimal Code 128 encoder (subsets B and C). Core Image's Code 128 generator
/// doesn't exist on watchOS, so this produces the same symbology directly.
enum Code128Barcode {
    /// Bar/space widths (in modules) for symbol values 0...105, then Stop.
    private static let patterns: [String] = [
        "212222", "222122", "222221", "121223", "121322", "131222", "122213", "122312", "132212", "221213",
        "221312", "231212", "112232", "122132", "122231", "113222", "123122", "123221", "223211", "221132",
        "221231", "213212", "223112", "312131", "311222", "321122", "321221", "312212", "322112", "322211",
        "212123", "212321", "232121", "111323", "131123", "131321", "112313", "132113", "132311", "211313",
        "231113", "231311", "112133", "112331", "132131", "113123", "113321", "133121", "313121", "211331",
        "231131", "213113", "213311", "213131", "311123", "311321", "331121", "312113", "312311", "332111",
        "314111", "221411", "431111", "111224", "111422", "121124", "121421", "141122", "141221", "112214",
        "112412", "122114", "122411", "142112", "142211", "241211", "221114", "413111", "241112", "134111",
        "111242", "121142", "121241", "114212", "124112", "124211", "411212", "421112", "421211", "212141",
        "214121", "412121", "111143", "111341", "131141", "114113", "114311", "411113", "411311", "113141",
        "114131", "311141", "411131", "211412", "211214", "211232",
    ]
    private static let stopPattern = "2331112"
    private static let startB = 104, startC = 105, switchToB = 100

    /// Formats input so the encoded barcode value ALWAYS reads `491(TM ID)0`.
    static func formatBarcodeValue(for input: String) -> String {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }
        if cleaned.hasPrefix("491") && cleaned.hasSuffix("0") && cleaned.count > 4 {
            return cleaned
        }
        if cleaned.hasPrefix("491") {
            return cleaned + "0"
        }
        if cleaned.hasSuffix("0") {
            return "491" + cleaned
        }
        return "491\(cleaned)0"
    }

    /// Symbol values for `message`, including start; checksum is added by caller.
    static func symbolValues(for rawMessage: String) -> [Int]? {
        let message = formatBarcodeValue(for: rawMessage)
        let scalars = Array(message.unicodeScalars)
        guard !scalars.isEmpty, scalars.allSatisfy({ $0.value >= 32 && $0.value <= 126 }) else { return nil }

        let digits = scalars.map { $0.value >= 48 && $0.value <= 57 ? Int($0.value) - 48 : -1 }
        let allDigits = !digits.contains(-1)

        var values: [Int] = []
        if allDigits && digits.count >= 4 {
            values.append(startC)
            var index = 0
            while index + 1 < digits.count {
                values.append(digits[index] * 10 + digits[index + 1])
                index += 2
            }
            if index < digits.count {
                values.append(switchToB)
                values.append(Int(scalars[index].value) - 32)
            }
        } else {
            values.append(startB)
            values.append(contentsOf: scalars.map { Int($0.value) - 32 })
        }
        return values
    }

    /// One Bool per module: `true` = bar.
    /// Includes standard Code 128 quiet zones (10 modules of space) on both ends for reliable scanning.
    static func modules(for message: String) -> [Bool]? {
        guard var values = symbolValues(for: message) else { return nil }
        var checksum = values[0]
        for (position, value) in values.enumerated().dropFirst() {
            checksum += position * value
        }
        values.append(checksum % 103)

        var modules: [Bool] = []

        // Quiet zone at start (10 modules of space)
        modules.append(contentsOf: Array(repeating: false, count: 10))

        func append(_ pattern: String) {
            var isBar = true
            for character in pattern {
                modules.append(contentsOf: Array(repeating: isBar, count: Int(String(character))!))
                isBar.toggle()
            }
        }
        for value in values { append(patterns[value]) }
        append(stopPattern)

        // Quiet zone at end (10 modules of space)
        modules.append(contentsOf: Array(repeating: false, count: 10))

        return modules
    }
}

/// The whole rect as one solid block with every bar cut out as a hole (fill it
/// with `FillStyle(eoFill: true)`). Watch faces recolor widgets using only each
/// pixel's opacity, so a black-on-white bitmap turns into a flat white
/// rectangle there; holes survive every rendering mode and read as dark bars on
/// a light block. Being a vector, it also fills any slot size exactly with no
/// aspect-ratio or scaling math.
struct Code128Shape: Shape {
    let modules: [Bool]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        guard !modules.isEmpty else { return path }

        let moduleWidth = rect.width / CGFloat(modules.count)
        var index = 0
        while index < modules.count {
            guard modules[index] else { index += 1; continue }
            var end = index
            while end < modules.count && modules[end] { end += 1 }
            path.addRect(CGRect(
                x: rect.minX + CGFloat(index) * moduleWidth,
                y: rect.minY,
                width: CGFloat(end - index) * moduleWidth,
                height: rect.height
            ))
            index = end
        }
        return path
    }
}

/// Just the bars, no backing block. Filled with `Color.primary` it draws black
/// bars in light mode and white bars in dark mode, so a widget with a
/// transparent background stays readable against either.
struct Code128BarsShape: Shape {
    let modules: [Bool]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !modules.isEmpty else { return path }

        let moduleWidth = rect.width / CGFloat(modules.count)
        var index = 0
        while index < modules.count {
            guard modules[index] else { index += 1; continue }
            var end = index
            while end < modules.count && modules[end] { end += 1 }
            path.addRect(CGRect(
                x: rect.minX + CGFloat(index) * moduleWidth,
                y: rect.minY,
                width: CGFloat(end - index) * moduleWidth,
                height: rect.height
            ))
            index = end
        }
        return path
    }
}
