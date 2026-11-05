import SwiftUI

/// CS Sup–only tab: Cash Office and safe codes. Reveal requires Face ID / Touch ID.
struct KeysView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @State private var revealedIDs: Set<String> = []
    @State private var authMessage: String?

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
                        Text("Tap a row to reveal the code with Face ID or your device passcode. Tap again to hide.")
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
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    (Text(LocalizedStringKey(item.title)) + Text("."))
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.primary)
                    if let detail = item.detail {
                        Text(LocalizedStringKey(detail))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text(displayCode(for: item, revealed: revealed))
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
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
            withAnimation(.easeInOut(duration: 0.15)) {
                revealedIDs.remove(item.id)
            }
            return
        }

        Task { @MainActor in
            let reason = String(format: String(localized: "Unlock to view the %@ code"), item.title)
            switch await BiometricAuth.authenticate(reason: reason) {
            case .success:
                withAnimation(.easeInOut(duration: 0.15)) {
                    revealedIDs.insert(item.id)
                }
            case .cancelled:
                break
            case .failed:
                authMessage = String(localized: "Authentication didn’t work. Try again.")
            case .unavailable:
                authMessage = String(localized: "Face ID isn’t available on this device. Set up Face ID or a passcode in Settings.")
            }
        }
    }

    private func displayCode(for item: StoreKeyItem, revealed: Bool) -> String {
        guard revealed else { return StoreKeysCatalog.masked }
        if item.isConfigured { return item.code }
        return "—"
    }
}
