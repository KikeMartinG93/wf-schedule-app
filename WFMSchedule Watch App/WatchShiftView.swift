import SwiftUI

/// What the watch app shows when it opens: only a countdown. While a shift is
/// happening the whole screen is green and a line rises from the bottom as the
/// shift goes by, filling the screen at 100%, with the time left until it ends.
/// Otherwise it's a plain black screen with the time until the next shift.
struct WatchShiftView: View {
    @ObservedObject private var receiver = WatchBarcodeReceiver.shared

    var body: some View {
        // The fill moves a fraction of a point a minute over a whole shift, so a
        // 30-second refresh is smooth enough and easy on the battery; the
        // countdown text ticks on its own.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let state = ShiftClockState.state(at: context.date, shifts: receiver.shifts)
            ZStack {
                background(for: state, now: context.date)
                content(for: state, now: context.date)
            }
        }
        .fontDesign(receiver.roundedFont ? .rounded : .default)
    }

    // MARK: - Background

    private let deepGreen = Color(red: 0.04, green: 0.24, blue: 0.11)
    private let elapsedGreen = Color(red: 0.11, green: 0.52, blue: 0.24)
    private let lineGreen = Color(red: 0.42, green: 0.93, blue: 0.55)

    @ViewBuilder
    private func background(for state: ShiftClockState, now: Date) -> some View {
        switch state {
        case .onShift(let start, let end):
            let progress = ShiftClockState.progress(start: start, end: end, now: now)
            let mono = receiver.highContrast
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    (mono ? Color.black : deepGreen)
                    // Time already worked, rising from the bottom.
                    Rectangle()
                        .fill(mono ? Color(white: 0.32) : elapsedGreen)
                        .frame(height: proxy.size.height * progress)
                        .overlay(alignment: .top) {
                            if progress > 0 && progress < 1 {
                                Rectangle()
                                    .fill(mono ? Color.white : lineGreen)
                                    .frame(height: 3)
                            }
                        }
                }
            }
            .ignoresSafeArea()
        case .upcoming, .none:
            Color.black.ignoresSafeArea()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(for state: ShiftClockState, now: Date) -> some View {
        switch state {
        case .onShift(_, let end):
            countdown(label: "Shift ends in", target: end, now: now)
        case .upcoming(let start):
            countdown(label: "Next shift in", target: start, now: now)
        case .none:
            Text("No upcoming shifts")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding()
        }
    }

    private func countdown(label: LocalizedStringKey, target: Date, now: Date) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.85))
            if target.timeIntervalSince(now) >= 86_400 {
                Text(target, style: .relative)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
            } else {
                Text(target, style: .timer)
                    .font(.system(size: 44, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        .padding(.horizontal, 8)
        .multilineTextAlignment(.center)
    }
}
