import SwiftUI

/// High-contrast shift marks use stroke *patterns* instead of color so jobs
/// stay distinguishable when the palette collapses to black / white / gray.
enum ShiftIndicatorPattern: Hashable, CaseIterable {
    case solid
    case dashed
    case dotted
    case wavy
    case zigzag
    case double

    /// Stable assignment per job name. Supervisor / Cash Office stay fixed;
    /// everything else cycles the remaining refined strokes.
    static func forJob(_ job: String) -> ShiftIndicatorPattern {
        switch job {
        case "Supervisor": return .solid
        case "Cash Office": return .dashed
        default:
            let rest: [ShiftIndicatorPattern] = [.dotted, .wavy, .zigzag, .double]
            return rest[stableHash(job) % rest.count]
        }
    }

    static func forSpecial(_ key: String) -> ShiftIndicatorPattern {
        switch key {
        case ShiftIndicatorKey.holiday: return .dotted
        case ShiftIndicatorKey.payday: return .double
        case ShiftIndicatorKey.periodStart: return .dashed
        case ShiftIndicatorKey.periodEnd: return .zigzag
        default: return .solid
        }
    }

    private static func stableHash(_ string: String) -> Int {
        var hash = 5381
        for byte in string.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(byte)
        }
        return abs(hash)
    }
}

enum ShiftIndicatorKey {
    static let holiday = "__holiday__"
    static let payday = "__payday__"
    static let periodStart = "__periodStart__"
    static let periodEnd = "__periodEnd__"

    static func pattern(for key: String) -> ShiftIndicatorPattern {
        if key.hasPrefix("__") { return .forSpecial(key) }
        return .forJob(key)
    }
}

/// Compact horizontal mark: solid capsule in color mode, patterned stroke in high contrast.
struct ShiftIndicatorBar: View {
    let key: String
    var color: Color
    var highContrast: Bool
    var width: CGFloat = 48
    var height: CGFloat = 4

    var body: some View {
        Group {
            if highContrast {
                ShiftIndicatorStroke(pattern: ShiftIndicatorKey.pattern(for: key))
                    .stroke(Color.primary, style: ShiftIndicatorStroke.style(for: ShiftIndicatorKey.pattern(for: key), lineWidth: height * 0.42))
                    .frame(width: width, height: height)
            } else if key == ShiftIndicatorKey.holiday {
                Capsule()
                    .fill(HolidayPayStyle.gradient)
                    .frame(width: width, height: height)
            } else {
                Capsule()
                    .fill(color)
                    .frame(width: width, height: height)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Drawable stroke geometry for each pattern, sized to the view’s bounds.
struct ShiftIndicatorStroke: Shape {
    var pattern: ShiftIndicatorPattern

    func path(in rect: CGRect) -> Path {
        let insetX = rect.height * 0.15
        let usable = CGRect(
            x: rect.minX + insetX,
            y: rect.minY,
            width: max(0, rect.width - insetX * 2),
            height: rect.height
        )
        switch pattern {
        case .solid, .dashed, .dotted, .double:
            return capsuleCenterline(in: usable)
        case .wavy:
            return wave(in: usable)
        case .zigzag:
            return zigzag(in: usable)
        }
    }

    static func style(for pattern: ShiftIndicatorPattern, lineWidth: CGFloat) -> StrokeStyle {
        let width = max(1.2, lineWidth)
        switch pattern {
        case .solid, .wavy, .zigzag:
            return StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        case .dashed:
            return StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: [5.5, 3.2])
        case .dotted:
            return StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: [0.01, width * 2.1])
        case .double:
            // Drawn as a single thicker dashed “rail”; the shape adds a parallel line.
            return StrokeStyle(lineWidth: width * 0.72, lineCap: .round, lineJoin: .round)
        }
    }

    private func capsuleCenterline(in rect: CGRect) -> Path {
        var path = Path()
        let y = rect.midY
        if pattern == .double {
            let gap = max(1.1, rect.height * 0.28)
            path.move(to: CGPoint(x: rect.minX, y: y - gap))
            path.addLine(to: CGPoint(x: rect.maxX, y: y - gap))
            path.move(to: CGPoint(x: rect.minX, y: y + gap))
            path.addLine(to: CGPoint(x: rect.maxX, y: y + gap))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }

    private func wave(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let amplitude = min(rect.height * 0.38, 1.6)
        let wavelength = max(7.0, rect.width / 5.5)
        path.move(to: CGPoint(x: rect.minX, y: midY))
        var x = rect.minX
        var rising = true
        while x < rect.maxX - 0.5 {
            let next = min(rect.maxX, x + wavelength * 0.5)
            let control = CGPoint(
                x: (x + next) * 0.5,
                y: midY + (rising ? -amplitude : amplitude)
            )
            path.addQuadCurve(to: CGPoint(x: next, y: midY), control: control)
            x = next
            rising.toggle()
        }
        return path
    }

    private func zigzag(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let amplitude = min(rect.height * 0.42, 1.7)
        let step = max(5.5, rect.width / 7.0)
        path.move(to: CGPoint(x: rect.minX, y: midY + amplitude * 0.35))
        var x = rect.minX
        var up = true
        while x < rect.maxX - 0.5 {
            let next = min(rect.maxX, x + step)
            path.addLine(to: CGPoint(
                x: next,
                y: midY + (up ? -amplitude : amplitude)
            ))
            x = next
            up.toggle()
        }
        return path
    }
}
