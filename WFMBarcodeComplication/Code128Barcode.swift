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
    private static let startB = 104, startC = 105, switchToB = 100, switchToC = 99

    /// Formats input so the encoded barcode value ALWAYS reads `0491(TM ID)00`.
    static func formatBarcodeValue(for input: String) -> String {
        let cleaned = input.filter { $0.isNumber }
        guard !cleaned.isEmpty else { return "" }
        if cleaned.count == 13 && cleaned.hasPrefix("0491") {
            return cleaned
        }
        if cleaned.count == 12 && cleaned.hasPrefix("491") {
            return "0" + cleaned
        }
        if cleaned.hasPrefix("0491") {
            let body = String(cleaned.dropFirst(4))
            let tm = body.count < 7 ? String(repeating: "0", count: 7 - body.count) + body : body
            return "0491\(tm)00"
        }
        if cleaned.hasPrefix("491") {
            let body = String(cleaned.dropFirst(3))
            let tm = body.count < 7 ? String(repeating: "0", count: 7 - body.count) + body : body
            return "0491\(tm)00"
        }
        let tm = cleaned.count < 7 ? String(repeating: "0", count: 7 - cleaned.count) + cleaned : cleaned
        return "0491\(tm)00"
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
            if digits.count % 2 == 0 {
                values.append(startC)
                var index = 0
                while index < digits.count {
                    values.append(digits[index] * 10 + digits[index + 1])
                    index += 2
                }
            } else {
                values.append(startB)
                values.append(digits[0] + 16)
                values.append(switchToC)
                var index = 1
                while index + 1 < digits.count {
                    values.append(digits[index] * 10 + digits[index + 1])
                    index += 2
                }
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


// MARK: - UPC-A Barcode (Whole Foods Market Discount Card)

/// UPC-A Barcode encoder and renderer matching the official Whole Foods Market
/// discount card standard.
///
/// A UPC-A symbol encodes 12 decimal digits:
/// - Digit 0: Number system character ("4" for store discount cards)
/// - Digits 1-5: Left-hand data characters (e.g. "91***")
/// - Digits 6-10: Right-hand data characters (e.g. "*****")
/// - Digit 11: Modulo-10 check digit (e.g. "0")
///
/// Total modules:
/// - Start guard: 101 (3 modules, tall)
/// - Left 6 digits: 6 * 7 = 42 modules (L-code, normal height)
/// - Center guard: 01010 (5 modules, tall)
/// - Right 6 digits: 6 * 7 = 42 modules (R-code, normal height)
/// - End guard: 101 (3 modules, tall)
/// Total barcode modules = 95.
/// Quiet zones: 10 modules left, 10 modules right -> 115 total modules.
enum UPCABarcode {
    private static let lPatterns: [String] = [
        "0001101", "0011001", "0010011", "0111101", "0100011",
        "0110001", "0101111", "0111011", "0110111", "0001011"
    ]
    private static let rPatterns: [String] = [
        "1110010", "1100110", "1101100", "1000010", "1011100",
        "1001110", "1010000", "1000100", "1001000", "1110100"
    ]

    static func calculateCheckDigit(for d11: String) -> Int {
        let digits = d11.compactMap { $0.wholeNumberValue }
        guard digits.count >= 11 else { return 0 }
        var odds = 0
        var evens = 0
        for i in 0..<11 {
            if i % 2 == 0 {
                odds += digits[i]
            } else {
                evens += digits[i]
            }
        }
        let total = (odds * 3) + evens
        let rem = total % 10
        return rem == 0 ? 0 : (10 - rem)
    }

    /// Formats input into the canonical 12-digit UPC-A string.
    /// Encodes `491(TM ID)0(check)` so POS/register scanners reading EAN-13
    /// read exactly `0491(TM ID)00` (e.g. `0491261648900` for TM ID `2616489`).
    static func formatDigits(for input: String) -> String {
        var cleaned = input.filter { $0.isNumber }
        guard !cleaned.isEmpty else { return "" }

        // Strip leading "0" if 13 digits starting with 0 or prefixed with "0491"
        if cleaned.count == 13 && cleaned.hasPrefix("0") {
            cleaned = String(cleaned.dropFirst())
        } else if cleaned.hasPrefix("0491") {
            cleaned = String(cleaned.dropFirst())
        }

        // If 12 digits, return as-is
        if cleaned.count == 12 { return cleaned }

        // If 11 digits, calculate and append check digit
        if cleaned.count == 11 {
            return cleaned + String(calculateCheckDigit(for: cleaned))
        }

        // If prefixed with "491"
        if cleaned.hasPrefix("491") {
            let body = String(cleaned.dropFirst(3))
            if body.count == 7 {
                let d11 = "491" + body + "0"
                return d11 + String(calculateCheckDigit(for: d11))
            }
            if body.count == 8 {
                let d11 = "491" + body
                return d11 + String(calculateCheckDigit(for: d11))
            }
            if body.count < 7 {
                let padded = String(repeating: "0", count: 7 - body.count) + body
                let d11 = "491" + padded + "0"
                return d11 + String(calculateCheckDigit(for: d11))
            }
        }

        // Standard TM ID entered in settings (e.g. 7 digits like "2616489")
        if cleaned.count <= 7 {
            let tmID = String(repeating: "0", count: max(0, 7 - cleaned.count)) + cleaned
            let d11 = "491" + tmID + "0"
            return d11 + String(calculateCheckDigit(for: d11))
        } else if cleaned.count == 8 {
            let d11 = "491" + cleaned
            return d11 + String(calculateCheckDigit(for: d11))
        }

        let d11 = String(cleaned.prefix(11)).padding(toLength: 11, withPad: "0", startingAt: 0)
        return d11 + String(calculateCheckDigit(for: d11))
    }

    /// Deconstructs the 12 digits for masked presentation matching the official card:
    /// `4   91*** *****   0`
    static func maskedLabels(for input: String) -> (prefix: String, left: String, right: String, check: String)? {
        let digits = formatDigits(for: input)
        guard digits.count == 12 else { return nil }
        let d = Array(digits)
        let prefix = String(d[0])
        let left = String(d[1...2]) + "***"
        let right = "*****"
        let check = String(d[11])
        return (prefix, left, right, check)
    }

    struct Module: Equatable {
        let isBar: Bool
        let isTall: Bool
    }

    /// Returns the 95 modules (isBar, isTall).
    static func modules(for input: String) -> [Module]? {
        let digits = formatDigits(for: input)
        guard digits.count == 12 else { return nil }
        let d = digits.compactMap { $0.wholeNumberValue }
        guard d.count == 12 else { return nil }

        var result: [Module] = []
        // Start guard: 101 (tall)
        for c in "101" { result.append(Module(isBar: c == "1", isTall: true)) }
        // Left 6 digits (L-patterns, normal)
        for i in 0..<6 {
            let pat = lPatterns[d[i]]
            for c in pat { result.append(Module(isBar: c == "1", isTall: false)) }
        }
        // Center guard: 01010 (tall bars)
        for c in "01010" { result.append(Module(isBar: c == "1", isTall: true)) }
        // Right 6 digits (R-patterns, normal)
        for i in 6..<12 {
            let pat = rPatterns[d[i]]
            for c in pat { result.append(Module(isBar: c == "1", isTall: false)) }
        }
        // End guard: 101 (tall)
        for c in "101" { result.append(Module(isBar: c == "1", isTall: true)) }

        return result
    }
}

/// Vector shape rendering UPC-A barcode bars with accurate guard bar extension.
struct UPCABarsShape: Shape {
    let modules: [UPCABarcode.Module]
    var quietModules: CGFloat = 10
    var dataHeightRatio: CGFloat = 0.81
    var guardHeightRatio: CGFloat = 0.94

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !modules.isEmpty else { return path }
        let totalModules = CGFloat(modules.count) + quietModules * 2
        let moduleWidth = rect.width / totalModules
        let startX = rect.minX + quietModules * moduleWidth

        var index = 0
        while index < modules.count {
            guard modules[index].isBar else {
                index += 1
                continue
            }
            let isTall = modules[index].isTall
            var end = index
            while end < modules.count && modules[end].isBar && modules[end].isTall == isTall {
                end += 1
            }
            let h = rect.height * (isTall ? guardHeightRatio : dataHeightRatio)
            let x = startX + CGFloat(index) * moduleWidth
            let w = CGFloat(end - index) * moduleWidth
            path.addRect(CGRect(x: x, y: rect.minY, width: w, height: h))
            index = end
        }
        return path
    }
}

/// Solid block with barcode holes cut out for accessory complications / Lock Screen tinted rendering.
/// Features extended guard bars and data notches matching standard UPC-A geometry.
struct UPCAShape: Shape {
    let modules: [UPCABarcode.Module]
    var quietModules: CGFloat = 8
    var dataHeightRatio: CGFloat = 0.81
    var guardHeightRatio: CGFloat = 0.94

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        guard !modules.isEmpty else { return path }

        let totalModules = CGFloat(modules.count) + quietModules * 2
        let moduleWidth = rect.width / totalModules
        let startX = rect.minX + quietModules * moduleWidth

        var index = 0
        while index < modules.count {
            guard modules[index].isBar else {
                index += 1
                continue
            }
            let isTall = modules[index].isTall
            var end = index
            while end < modules.count && modules[end].isBar && modules[end].isTall == isTall {
                end += 1
            }
            let h = rect.height * (isTall ? guardHeightRatio : dataHeightRatio)
            let x = startX + CGFloat(index) * moduleWidth
            let w = CGFloat(end - index) * moduleWidth
            path.addRect(CGRect(x: x, y: rect.minY, width: w, height: h))
            index = end
        }
        return path
    }
}

/// The complete discount card barcode display matching the official Whole Foods Market
/// electronic discount card: pure white card, UPC-A bars with extended guard bars,
/// and masked numbers formatted exactly as `4   91*** *****   0`.
struct UPCABarcodeCard: View {
    let input: String

    var body: some View {
        if let modules = UPCABarcode.modules(for: input) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let totalModules: CGFloat = 115
                let moduleWidth = w / totalModules

                ZStack(alignment: .topLeading) {
                    // White card backing
                    Color.white

                    // UPC-A Bars with extended guard bars and data notches
                    UPCABarsShape(modules: modules, quietModules: 10, dataHeightRatio: 0.81, guardHeightRatio: 0.94)
                        .fill(Color.black)

                    // Digits matching official discount card: 4  91***  *****  0
                    if let labels = UPCABarcode.maskedLabels(for: input) {
                        let fontSize = max(8, min(h * 0.17, moduleWidth * 4.4))

                        // Digit 0 (prefix "4" outside left guard)
                        Text(labels.prefix)
                            .font(.system(size: fontSize, weight: .regular, design: .default))
                            .foregroundStyle(Color.black)
                            .position(x: 6.2 * moduleWidth, y: h * 0.90)

                        // Left group ("91***" under left data bars)
                        Text(labels.left)
                            .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.black)
                            .frame(width: 42 * moduleWidth)
                            .position(x: 34.0 * moduleWidth, y: h * 0.90)

                        // Right group ("*****" under right data bars)
                        Text(labels.right)
                            .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.black)
                            .frame(width: 42 * moduleWidth)
                            .position(x: 81.0 * moduleWidth, y: h * 0.90)

                        // Check digit (e.g. "0" outside right guard)
                        Text(labels.check)
                            .font(.system(size: fontSize, weight: .regular, design: .default))
                            .foregroundStyle(Color.black)
                            .position(x: 108.8 * moduleWidth, y: h * 0.90)
                    }
                }
            }
        }
    }
}
