import SwiftUI
import WidgetKit

/// A swipeable gallery of every widget and the watch complication, each drawn
/// with the real widget view on sample data (never the real TM ID) inside a small
/// scene: a Lock Screen, a Home Screen, or a watch face. Every scene is the same
/// size so the cards line up and snap into place.
struct WidgetShowcase: View {
    @ObservedObject private var theme = ThemeManager.shared

    private let now = Date()
    private let cardWidth: CGFloat = 250
    private let sceneHeight: CGFloat = 164

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                card(kind: "Apple Watch", title: "Discount Barcode",
                     caption: "Scan your discount right from your wrist.") { watchScene }
                card(kind: "Home Screen", title: "Discount Barcode",
                     caption: "A transparent widget with your barcode, ready at the register.") { homeBarcodeScene }
                card(kind: "Lock Screen", title: "Discount Barcode",
                     caption: "Your barcode on the Lock Screen, no unlocking needed.") { lockScene { lockBarcode } }
                card(kind: "Lock Screen", title: "Next Shift",
                     caption: "Your next shift and how long until it starts.") { lockScene { lockNextShift } }
                card(kind: "Lock Screen", title: "Break Timer",
                     caption: "Time until your next break, red and pulsing when overdue.") { lockScene { lockBreak } }
                card(kind: "Home Screen", title: "Break Timer",
                     caption: "A bigger countdown that shifts from green to red.") { homeBreakScene }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollTargetBehavior(.viewAligned)
    }

    // MARK: - Card

    private func card<Scene: View>(kind: LocalizedStringKey, title: LocalizedStringKey, caption: LocalizedStringKey,
                                   @ViewBuilder scene: () -> Scene) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            scene()
                .frame(width: cardWidth, height: sceneHeight)
                .clipShape(.rect(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(kind)
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(theme.current.readableAccent)
                Text(title)
                    .font(.headline)
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(width: cardWidth, height: 84, alignment: .topLeading)
        }
        .frame(width: cardWidth, alignment: .topLeading)
    }

    /// Scales a widget drawn at its real point size down (or up) without letting
    /// the unscaled layout size leak out and push neighbouring cards around.
    private func scaled<Content: View>(_ size: CGSize, _ scale: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale)
            .frame(width: size.width * scale, height: size.height * scale)
    }

    // MARK: - Scenes

    private var accent: Color { theme.current.accent }
    private var deep: Color { theme.current.backgroundTint }

    private var sceneBackground: some View {
        LinearGradient(colors: [accent.opacity(0.9), deep.opacity(0.95)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .topTrailing) {
                Circle().fill(.white.opacity(0.14)).frame(width: 150).blur(radius: 30).offset(x: 30, y: -40)
            }
    }

    /// A tiny Lock Screen: the date and time over the wallpaper, widget below.
    private func lockScene<Widget: View>(@ViewBuilder _ widget: () -> Widget) -> some View {
        ZStack {
            sceneBackground
            VStack(spacing: 8) {
                VStack(spacing: 0) {
                    Text(verbatim: "Mon, Sep 21")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(verbatim: "9:41")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                widget()
                    .padding(8)
                    .background(.white.opacity(0.14), in: .rect(cornerRadius: 14, style: .continuous))
            }
            .padding(.top, 4)
        }
        .environment(\.colorScheme, .dark)
    }

    private var lockWidgetSize: CGSize { CGSize(width: 172, height: 76) }

    private var lockBarcode: some View {
        scaled(lockWidgetSize, 0.9) {
            BarcodeWidgetView(entry: BarcodeWidgetEntry(date: now, tmID: "1234567"), familyOverride: .accessoryRectangular)
        }
    }

    private var lockNextShift: some View {
        scaled(lockWidgetSize, 0.9) {
            NextShiftView(entry: NextShiftEntry(date: now, shift: sampleShift), familyOverride: .accessoryRectangular)
        }
    }

    private var lockBreak: some View {
        scaled(lockWidgetSize, 0.9) {
            BreakWidgetView(entry: BreakEntry(date: now,
                                              status: .upcoming(due: now.addingTimeInterval(35 * 60), number: 2, duration: 30),
                                              pulseOn: false),
                            familyOverride: .accessoryRectangular)
        }
    }

    private var homeBarcodeScene: some View {
        ZStack {
            sceneBackground
            scaled(CGSize(width: 338, height: 158), 0.66) {
                BarcodeWidgetView(entry: BarcodeWidgetEntry(date: now, tmID: "1234567"), familyOverride: .systemMedium)
                    .padding(16)
            }
            .background(.white.opacity(0.16), in: .rect(cornerRadius: 22, style: .continuous))
        }
        .environment(\.colorScheme, .dark)
    }

    private var homeBreakScene: some View {
        ZStack {
            sceneBackground
            let entry = BreakEntry(date: now,
                                   status: .upcoming(due: now.addingTimeInterval(12 * 60), number: 2, duration: 30),
                                   pulseOn: false)
            scaled(CGSize(width: 158, height: 158), 0.86) {
                BreakWidgetView(entry: entry, familyOverride: .systemSmall)
                    .padding(16)
                    .background { BreakWidgetBackground(entry: entry) }
                    .clipShape(.rect(cornerRadius: 24, style: .continuous))
            }
            .environment(\.colorScheme, .light)
        }
        .environment(\.colorScheme, .dark)
    }

    /// An Apple Watch face with the barcode complication under the time.
    private var watchScene: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.20), Color(white: 0.06)], startPoint: .top, endPoint: .bottom)
            watchBody
        }
    }

    private var watchBody: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.black)
                .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.25)], startPoint: .top, endPoint: .bottom), lineWidth: 3))
                .frame(width: 128, height: 152)
                .overlay {
                    VStack(spacing: 8) {
                        Text(verbatim: "10:09")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        if let modules = Code128Barcode.modules(for: "49112345670") {
                            ZStack {
                                Color.black
                                Code128Shape(modules: modules)
                                    .fill(Color.white, style: FillStyle(eoFill: true))
                            }
                            .frame(width: 100, height: 32)
                            .clipShape(.rect(cornerRadius: 6, style: .continuous))
                        }
                    }
                }
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(white: 0.4))
                .frame(width: 6, height: 26)
                .offset(x: 5)
        }
        .frame(width: 140, height: 152)
    }

    // MARK: - Sample data

    private var sampleShift: Shift {
        let start = now.addingTimeInterval(22 * 3600)
        return Shift(ukgRecordId: nil, date: start, startTime: start, endTime: start.addingTimeInterval(8 * 3600),
                     job: "Supervisor", location: nil, kind: .regular, payCode: nil, notes: nil)
    }
}
