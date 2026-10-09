import SwiftUI
import WidgetKit

struct SettingsView: View {
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var showingCredentialForm = false
    @State private var showingBackupSignIn = false
    @State private var showingWelcome = false
    @State private var showingWhatsNew = false
    @State private var showingBreaks = false
    @State private var showingChecklist = false
    @AppStorage(DemoMode.storageKey) private var demoMode = false
    @ObservedObject private var theme = ThemeManager.shared
    @State private var versionTaps = 0
    @State private var lastVersionTap = Date.distantPast
    @State private var versionNote: LocalizedStringKey?
    @AppStorage(AppIconManager.unlockedKey) private var classicIconUnlocked = false
    @AppStorage(AppIconManager.classicKey) private var classicIconOn = false
    @AppStorage(AppLanguage.storageKey) private var language: String = AppLanguage.system.rawValue
    @AppStorage(FontPreference.key, store: FontPreference.store) private var roundedFont = true

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                // The title is a top bar, not a sibling above the Form, so content
                // scrolls up under it and fades out softly instead of being cut off
                // in a hard line.
                    Form {
                        // Account
                        Section {
                            if sessionManager.state == .authenticated {
                                Button(role: .destructive) {
                                    sessionManager.logOut()
                                } label: {
                                    row("Sign out", "rectangle.portrait.and.arrow.right", tint: .red)
                                }
                            }
                            Button {
                                showingBackupSignIn = true
                            } label: {
                                row("Sign in with Amazon (UKG Pro)", "person.badge.key")
                            }
                            Toggle(isOn: automaticSignInBinding) {
                                row("Automatic background sign-in", "arrow.triangle.2.circlepath")
                            }
                            .tint(theme.current.toggleTint)
                        } header: {
                            Text("Account")
                        } footer: {
                            Text("Amazon sign-in is a backup if Innerview Login isn't working. Automatic sign-in keeps your UKG username and password in this device's Keychain so the app can sign back in on its own. Off by default.")
                        }

                        // Look and feel
                        Section {
                            if theme.highContrast {
                                Label("Colors are off while High contrast is on.", systemImage: "circle.lefthalf.filled")
                                    .foregroundStyle(.secondary)
                            } else {
                                ThemePicker()
                            }
                        } header: {
                            Text("Appearance")
                        }

                        Section {
                            Toggle(isOn: $theme.highContrast) {
                                row("High contrast", "circle.lefthalf.filled")
                            }
                            .tint(theme.current.toggleTint)
                            Toggle(isOn: roundedFontBinding) {
                                row("Rounded font", "textformat")
                            }
                            .tint(theme.current.toggleTint)
                            Picker(selection: languageBinding) {
                                Text("System default").tag(AppLanguage.system)
                                Text(verbatim: "English").tag(AppLanguage.en)
                                Text(verbatim: "Español").tag(AppLanguage.es)
                            } label: {
                                row("Language", "globe")
                            }
                            // A menu picker keeps the tint it was built with; without the
                            // id it stays green after High contrast is switched on live.
                            .tint(theme.current.readableAccent)
                            .id(theme.highContrast)
                        } header: {
                            Text("Display")
                        } footer: {
                            Text("High contrast turns the app, widgets and Live Activity plain black, white and gray. Some items, like dates and notifications, update after you restart the app.")
                        }

                        // Tools
                        Section {
                            Button {
                                showingBreaks = true
                            } label: {
                                row("Breaks & Calculator", "cup.and.saucer")
                            }
                            Button {
                                showingChecklist = true
                            } label: {
                                row("Daily Role Checklist", "checklist")
                            }
                        } header: {
                            Text("Tools")
                        } footer: {
                            Text("Plan break countdowns or track daily operational duties.")
                        }

                        Section {
                            TMIDField()
                        } header: {
                            Text("Discount Barcode")
                        } footer: {
                            Text("Kept in the secure Keychain and hidden once saved. Synced to your Apple Watch.")
                        }

                        Section {
                            WidgetShowcase()
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        } header: {
                            Text("Widgets")
                        } footer: {
                            Text("Long-press your Home Screen or Lock Screen, tap Add Widget, then search for WF Schedule. For the watch, edit a watch face and choose Discount Barcode. Previews use sample data.")
                        }

                        // Extras
                        Section {
                            Toggle(isOn: demoBinding) {
                                row("Demo mode", "sparkles")
                            }
                            .tint(theme.current.toggleTint)
                        } header: {
                            Text("Demo")
                        } footer: {
                            Text("Explore every feature with sample data. Nothing real is changed.")
                        }

                        // About
                        Section {
                            Button {
                                showingWelcome = true
                            } label: {
                                row("Show welcome screen", "hand.wave")
                            }
                            Button {
                                showingWhatsNew = true
                            } label: {
                                row("What's new", "wand.and.stars")
                            }
                            HStack {
                                row("Version", "info.circle")
                                Spacer()
                                if let versionNote {
                                    Text(versionNote)
                                        .foregroundStyle(theme.current.readableAccent)
                                } else {
                                    Text(appVersionString)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { versionTapped() }

                            if classicIconUnlocked {
                                Toggle(isOn: classicIconBinding) {
                                    row("WF Icon", "app.badge", verbatim: true)
                                }
                                .tint(theme.current.toggleTint)
                            }
                        } header: {
                            Text("About")
                        }
                    }
                    .scrollContentBackground(.hidden)
                    // Room to scroll the last rows clear of the floating shift bar.
                    .contentMargins(.bottom, 64, for: .scrollContent)
                    .safeAreaBar(edge: .top) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Settings")
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
            .sheet(isPresented: $showingCredentialForm) {
                AutoSignInCredentialForm()
            }
            .sheet(isPresented: $showingBackupSignIn) {
                UKGLoginView()
                    .tint(theme.current.readableAccent)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingBreaks) {
                BreaksView()
                    .tint(theme.current.readableAccent)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingChecklist) {
                ChecklistView()
                    .tint(theme.current.readableAccent)
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingWhatsNew) {
                WhatsNewView(items: WhatsNew.latestItems(), buttonTitle: "Done") { showingWhatsNew = false }
            }
            .sheet(isPresented: $showingWelcome) {
                WelcomeView(buttonTitle: "Done") { showingWelcome = false }
            }
        }
    }

    /// A settings row: a small tinted icon tile beside the title.
    private func row(_ title: LocalizedStringKey, _ symbol: String, tint: Color? = nil, verbatim: Bool = false) -> some View {
        Label {
            if verbatim { Text(verbatim: "WF Icon") } else { Text(title) }
        } icon: {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background((tint ?? theme.current.readableAccent).gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .foregroundStyle(tint == .red ? Color.red : Color.primary)
    }

    /// "Marketing version (build number)" — the build number is bumped on
    /// every release, so this always reflects exactly what's installed.
    private var appVersionString: String {
        let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(shortVersion) (\(build))"
    }

    private var classicIconBinding: Binding<Bool> {
        Binding(
            get: { classicIconOn },
            set: { AppIconManager.setClassic($0, themeID: ThemeManager.shared.current.id) }
        )
    }

    /// Easter egg: ten quick taps on the version number unlock the "WF Icon" toggle.
    private func versionTapped() {
        guard !classicIconUnlocked else { return }
        let now = Date()
        if now.timeIntervalSince(lastVersionTap) > 0.8 { versionTaps = 0 }
        lastVersionTap = now
        versionTaps += 1
        guard versionTaps >= 10 else { return }
        versionTaps = 0

        withAnimation { classicIconUnlocked = true }
        AppIconManager.setClassic(true, themeID: ThemeManager.shared.current.id)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation { versionNote = "WF Icon unlocked" }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { versionNote = nil }
        }
    }

    private var demoBinding: Binding<Bool> {
        Binding(get: { demoMode }, set: { DemoMode.set($0) })
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage(rawValue: language) ?? .system },
            set: { newValue in
                language = newValue.rawValue
                AppLanguage.apply(newValue)
            }
        )
    }

    private var roundedFontBinding: Binding<Bool> {
        Binding(
            get: { roundedFont },
            set: { newValue in
                roundedFont = newValue
                WidgetCenter.shared.reloadAllTimelines()
                BarcodePhoneSync.shared.send(BarcodeStore.value)
            }
        )
    }

    private var automaticSignInBinding: Binding<Bool> {
        Binding(
            get: { sessionManager.hasStoredCredentials },
            set: { newValue in
                if newValue {
                    showingCredentialForm = true
                } else {
                    sessionManager.disableAutomaticSignIn()
                }
            }
        )
    }
}

/// Grid of swatches for every `AppColorThemes.all` entry — tapping one sets
/// `ThemeManager.shared.current`, which every themed view across the app
/// (backgrounds, tab bar, selection accents) observes directly, so the whole
/// UI updates immediately with no extra plumbing here.
private struct ThemePicker: View {
    @ObservedObject private var theme = ThemeManager.shared

    private let columns = Array(repeating: GridItem(.flexible()), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(AppColorThemes.all) { candidate in
                Button {
                    theme.current = candidate
                } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(candidate.accent)
                            .frame(width: 32, height: 32)
                            .overlay {
                                // A checkmark, not just a ring, so the selection
                                // doesn't depend on telling colors apart.
                                if candidate.id == theme.current.id {
                                    Image(systemName: "checkmark")
                                        .font(.footnote.weight(.bold))
                                        .foregroundStyle(Color.onFill(candidate.accent))
                                }
                            }
                        Text(LocalizedStringKey(candidate.name))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(candidate.id == theme.current.id ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}

/// Entry for the TM ID. It's typed into a secure field, saved to the Keychain
/// (also pushed to the Watch and widgets), and from then on only ever shown as
/// "*****" — with a barcode preview so you can see it worked.
private struct TMIDField: View {
    // The Keychain is read once when the row appears and cached here. Reading it
    // in the property initializer or in `body` hit the Keychain on every redraw.
    @State private var isStored = false
    @State private var previewModules: [Bool]?
    @State private var isEditing = false
    @State private var draft = ""

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func refresh() {
        let id = BarcodeStore.value
        isStored = id != nil
        previewModules = id.flatMap { Code128Barcode.modules(for: $0) }
    }

    var body: some View {
        content
            .task { refresh() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isStored && !isEditing {
                HStack {
                    Label("TM ID", systemImage: "lock.fill")
                    Spacer()
                    Text(verbatim: SecureTMID.masked)
                        .foregroundStyle(.secondary)
                }

                preview

                HStack {
                    Button("Change") {
                        draft = ""
                        isEditing = true
                    }
                    Spacer()
                    Button("Remove", role: .destructive) {
                        BarcodeStore.value = nil
                        BarcodePhoneSync.shared.send(nil)
                        refresh()
                    }
                }
                .buttonStyle(.borderless)
            } else {
                SecureField("TM ID", text: $draft)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)

                HStack {
                    if isStored {
                        Button("Cancel") {
                            draft = ""
                            isEditing = false
                        }
                    }
                    Spacer()
                    Button("Save") {
                        BarcodeStore.value = trimmedDraft
                        BarcodePhoneSync.shared.send(BarcodeStore.value)
                        draft = ""
                        refresh()
                        isEditing = false
                    }
                    .disabled(trimmedDraft.isEmpty)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    /// The same Code 128 the widgets and watch draw: "491" + TM ID + "0".
    @ViewBuilder
    private var preview: some View {
        if let modules = previewModules {
            ZStack {
                Color.white
                Code128BarsShape(modules: modules)
                    .fill(Color.black)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct AutoSignInCredentialForm: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("UKG username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("UKG password", text: $password)
                } footer: {
                    Text("Stored only in this device's Keychain, used only to sign back into wfminc.prd.mykronos.com when your session expires.")
                }
            }
            .navigationTitle("Automatic Sign-In")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        sessionManager.enableAutomaticSignIn(username: username, password: password)
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(username.isEmpty || password.isEmpty)
                }
            }
        }
    }
}
