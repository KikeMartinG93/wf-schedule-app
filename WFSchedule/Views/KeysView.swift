import SwiftUI

/// CS Sup–only tab: Cash Office and safe codes. Reveal requires Face ID / Touch ID.
/// Codes auto-hide when leaving the tab, unlocking another key, or after 25 seconds.
struct KeysView: View {
    var isActive: Bool = true

    @ObservedObject private var theme = ThemeManager.shared
    @State private var revealedIDs: Set<String> = []
    @State private var authMessage: String?
    @State private var hideTask: Task<Void, Never>?

    /// 2.5× system body (~17pt) for the code glyphs inside each flip tile.
    private static let codePointSize: CGFloat = 17 * 2.5
    private static let autoHideSeconds: UInt64 = 25

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                Form {
                    Section {
                        ForEach(StoreKeysCatalog.cashOffice) { item in
                            keyRow(item)
                        }
                    } header: {
                        Text("Cash Office")
                    }

                    Section {
                        ForEach(StoreKeysCatalog.safes) { item in
                            keyRow(item)
                        }
                    } header: {
                        Text("Safes")
                    } footer: {
                        Text("Tap a row to reveal the code with Face ID or your device passcode. Codes hide when you leave Keys, unlock another code, or after 25 seconds.")
                    }
                }
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, 64, for: .scrollContent)
                .safeAreaBar(edge: .top) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Keys")
                            .font(.largeTitle.bold())
                            .foregroundStyle(Color(uiColor: .label))
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: isActive) { _, active in
                if !active { hideAllCodes() }
            }
            .onDisappear { hideAllCodes() }
            .alert("Couldn’t unlock", isPresented: Binding(
                get: { authMessage != nil },
                set: { if !$0 { authMessage = nil } }
            )) {
                Button("OK", role: .cancel) { authMessage = nil }
            } message: {
                Text(authMessage ?? "")
            }
        }
    }

    private func keyRow(_ item: StoreKeyItem) -> some View {
        let revealed = revealedIDs.contains(item.id)
        return Button {
            toggleReveal(item)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(item.title))
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.primary)
                    if let detail = item.detail {
                        Text(LocalizedStringKey(detail))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                FlipCodeDisplay(
                    characters: displayCharacters(for: item, revealed: revealed),
                    revealed: revealed && item.isConfigured,
                    pointSize: Self.codePointSize,
                    accent: theme.current.readableAccent
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: item.title))
        .accessibilityValue(Text(revealed && item.isConfigured
                                 ? item.code
                                 : String(localized: "Hidden")))
        .accessibilityHint("Requires Face ID to show the code")
    }

    private func toggleReveal(_ item: StoreKeyItem) {
        if revealedIDs.contains(item.id) {
            hideAllCodes()
            return
        }

        Task { @MainActor in
            let reason = String(format: String(localized: "Unlock to view the %@ code"), item.title)
            switch await BiometricAuth.authenticate(reason: reason) {
            case .success:
                // Only one code visible at a time — hide any previous reveal first.
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                    revealedIDs = [item.id]
                }
                scheduleAutoHide()
            case .cancelled:
                break
            case .failed:
                authMessage = String(localized: "Authentication didn’t work. Try again.")
            case .unavailable:
                authMessage = String(localized: "Face ID isn’t available on this device. Set up Face ID or a passcode in Settings.")
            }
        }
    }

    private func hideAllCodes() {
        hideTask?.cancel()
        hideTask = nil
        guard !revealedIDs.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            revealedIDs.removeAll()
        }
    }

    private func scheduleAutoHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.autoHideSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            hideAllCodes()
        }
    }

    private func displayCharacters(for item: StoreKeyItem, revealed: Bool) -> [Character] {
        if revealed {
            if item.isConfigured { return Array(item.code) }
            return ["—"]
        }
        let count = item.isConfigured ? max(item.code.count, 1) : StoreKeysCatalog.masked.count
        return Array(repeating: "•", count: count)
    }
}

// MARK: - Flip clock code

/// Row of flip-clock tiles for a key code. Digits cascade in when revealed.
private struct FlipCodeDisplay: View {
    let characters: [Character]
    let revealed: Bool
    let pointSize: CGFloat
    let accent: Color

    var body: some View {
        HStack(spacing: max(4, pointSize * 0.08)) {
            ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
                FlipDigitTile(
                    character: character,
                    revealed: revealed,
                    pointSize: pointSize,
                    accent: accent,
                    flipDelay: Double(index) * 0.045
                )
            }
        }
        .accessibilityHidden(true)
    }
}

private struct FlipDigitTile: View {
    let character: Character
    let revealed: Bool
    let pointSize: CGFloat
    let accent: Color
    let flipDelay: Double

    @State private var flapAngle: Double = -90

    private var tileWidth: CGFloat { pointSize * 0.78 }
    private var tileHeight: CGFloat { pointSize * 1.22 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: pointSize * 0.16, style: .continuous)
                .fill(tileFill)
                .overlay {
                    RoundedRectangle(cornerRadius: pointSize * 0.16, style: .continuous)
                        .strokeBorder(
                            revealed ? accent.opacity(0.35) : Color.primary.opacity(0.06),
                            lineWidth: revealed ? 1.5 : 1
                        )
                }
                .shadow(color: .black.opacity(revealed ? 0.18 : 0.06), radius: revealed ? 3 : 1, y: 1)

            Text(String(character))
                .font(.system(size: pointSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(revealed ? Color.primary : Color.secondary.opacity(0.55))
                .minimumScaleFactor(0.5)

            // Midline — classic split-flap seam.
            Rectangle()
                .fill(Color.primary.opacity(revealed ? 0.22 : 0.10))
                .frame(height: 1)
                .padding(.horizontal, 2)
                .allowsHitTesting(false)

            // Soft top highlight so the flap reads as two hinged halves.
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        Color.white.opacity(revealed ? 0.14 : 0.06),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: tileHeight / 2)
                Spacer(minLength: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: pointSize * 0.16, style: .continuous))
            .allowsHitTesting(false)
        }
        .frame(width: tileWidth, height: tileHeight)
        .rotation3DEffect(
            .degrees(flapAngle),
            axis: (x: 1, y: 0, z: 0),
            anchor: .center,
            perspective: 0.55
        )
        .onAppear { syncFlap(animated: false) }
        .onChange(of: revealed) { _, _ in syncFlap(animated: true) }
        .onChange(of: character) { _, _ in
            if revealed { bounceFlap() }
        }
    }

    private var tileFill: some ShapeStyle {
        if revealed {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(uiColor: .secondarySystemGroupedBackground),
                        Color(uiColor: .tertiarySystemGroupedBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        return AnyShapeStyle(Color.primary.opacity(0.06))
    }

    private func syncFlap(animated: Bool) {
        let target: Double = revealed ? 0 : -90
        if animated {
            flapAngle = revealed ? 90 : 0
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72).delay(flipDelay)) {
                flapAngle = target
            }
        } else {
            flapAngle = target
        }
    }

    private func bounceFlap() {
        flapAngle = 70
        withAnimation(.spring(response: 0.34, dampingFraction: 0.7).delay(flipDelay)) {
            flapAngle = 0
        }
    }
}
