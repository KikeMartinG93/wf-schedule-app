import SwiftUI
import WidgetKit
#if canImport(UIKit)
import UIKit
#endif

struct SettingsView: View {
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var showingCredentialForm = false
    @State private var showingSignIn = false
    @State private var showingWelcome = false
    @State private var showingOnboarding = false
    @State private var showingWhatsNew = false
    @State private var showingBreaks = false
    @State private var showingChecklist = false
    @State private var showingCSPasscode = false
    @State private var csPasscodeDraft = ""
    @State private var csPasscodeError = false
    @AppStorage(DemoMode.storageKey) private var demoMode = false
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var appearanceMode: ColorScheme = .dark
    @State private var versionTaps = 0
    @State private var lastVersionTap = Date.distantPast
    @State private var versionNote: LocalizedStringKey?
    @AppStorage(AppIconManager.unlockedKey) private var classicIconUnlocked = false
    @AppStorage(AppIconManager.classicKey) private var classicIconOn = false
    @AppStorage("themeSectionExpanded") private var isThemeExpanded = true
    @AppStorage(AppLanguage.storageKey) private var language: String = AppLanguage.system.rawValue
    @AppStorage(FontPreference.key, store: FontPreference.store) private var roundedFont = true
    @AppStorage("calendarDayTickerMode") private var calendarDayTickerMode = true
    @AppStorage("csSupKeysUnlocked") private var keysUnlocked = false
    @ObservedObject private var weatherStore = WorkWeatherStore.shared
    @State private var cloudBackup = SupabaseBackupService.shared
    @AppStorage("payPaymentMethod") private var payPaymentMethod = ""
    @AppStorage("payPaydayWeekday") private var payPaydayWeekday = ""

    private var payPreferencesSummary: String {
        switch PayPreferences.method {
        case .directDeposit:
            switch PayPreferences.weekday {
            case .wednesday: String(localized: "Wednesdays")
            case .friday: String(localized: "Fridays")
            case nil: String(localized: "Direct Deposit")
            }
        case .check:
            String(localized: "Check")
        case nil:
            String(localized: "Set up")
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                // The title is a top bar, not a sibling above the Form, so content
                // scrolls up under it and fades out softly instead of being cut off
                // in a hard line.
                Form {
                    // 1. Account & Security
                    Section {
                        if sessionManager.state == .authenticated {
                            Button(role: .destructive) {
                                sessionManager.logOut()
                            } label: {
                                row("Sign out", "rectangle.portrait.and.arrow.right", tint: .red)
                            }
                        } else {
                            Button {
                                showingSignIn = true
                            } label: {
                                row("Sign in with Amazon", "person.badge.key")
                            }
                        }
                        Toggle(isOn: automaticSignInBinding) {
                            row("Automatic background sign-in", "arrow.triangle.2.circlepath")
                        }
                        .tint(theme.current.toggleTint)
                    } header: {
                        Text("Account")
                    } footer: {
                        Text("Automatic sign-in securely stores credentials in Keychain to keep your schedule refreshed in the background.")
                    }

                    // 2. Cloud backup (Supabase — separate from Amazon / UKG)
                    Section {
                        NavigationLink {
                            CloudBackupSettingsView()
                        } label: {
                            HStack {
                                row("Cloud backup", "icloud.and.arrow.up")
                                Spacer()
                                Text(cloudBackup.isSignedIn
                                     ? (cloudBackup.email ?? "On")
                                     : "Off")
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    } header: {
                        Text("Cloud Backup")
                    } footer: {
                        Text("Optional email account that backs up your shift history so it survives reinstalls. Separate from Amazon sign-in.")
                    }

                    // 3. Discount Barcode
                    Section {
                        TMIDField()
                    } header: {
                        Text("Discount Barcode")
                    } footer: {
                        Text("Stored securely in the Keychain for quick access and widgets.")
                    }

                    // 3. Theme & Appearance (Collapsible)
                    Section {
                        DisclosureGroup(isExpanded: $isThemeExpanded) {
                            NavigationLink {
                                AppearanceSettingsView()
                            } label: {
                                HStack {
                                    row("Appearance", "iphone")
                                    Spacer()
                                    Text(theme.currentDisplayStyle.name)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if theme.highContrast {
                                Label("Colors are off while High contrast is on.", systemImage: "circle.lefthalf.filled")
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 4)
                            } else {
                                Picker("Appearance Mode", selection: $appearanceMode) {
                                    Label("Light Mode", systemImage: "sun.max.fill").tag(ColorScheme.light)
                                    Label("Dark Mode", systemImage: "moon.fill").tag(ColorScheme.dark)
                                }
                                .pickerStyle(.segmented)
                                .padding(.vertical, 4)

                                ThemePicker(scheme: appearanceMode)

                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        row("Gradient vibrancy", "slider.horizontal.3")
                                        Spacer()
                                        Text(theme.vibrancy(for: appearanceMode), format: .percent.precision(.fractionLength(0)))
                                            .font(.subheadline.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }

                                    Slider(
                                        value: Binding(
                                            get: { theme.vibrancy(for: appearanceMode) },
                                            set: { theme.setVibrancy($0, for: appearanceMode) }
                                        ),
                                        in: 0.0...1.0
                                    )
                                    .tint(theme.current(for: appearanceMode).readableAccent)
                                }
                                .padding(.top, 4)
                            }
                        } label: {
                            HStack {
                                row("Theme & Appearance", "paintpalette")
                                Spacer()
                                if !isThemeExpanded && !theme.highContrast {
                                    Text(LocalizedStringKey(theme.selectedTheme(for: appearanceMode).name))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Theme & Appearance")
                    } footer: {
                        if isThemeExpanded && !theme.highContrast {
                            Text(appearanceMode == .light
                                 ? "Pick Classic, Light, or Dark for the calendar, then a color palette and vibrancy for Light mode. Lowering the bar adds a white overlay for accessibility."
                                 : "Pick Classic, Light, or Dark for the calendar, then a color palette and vibrancy for Dark mode. Lowering the bar adds a black overlay for accessibility.")
                        }
                    }

                    // 4. Work city (forecast on Home)
                    Section {
                        NavigationLink {
                            WorkCityPicker()
                        } label: {
                            HStack {
                                row("Work city", "building.2")
                                Spacer()
                                Text(weatherStore.city?.displayName ?? "Choose a city")
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    } header: {
                        Text("Work Location")
                    } footer: {
                        Text("Home shows the high/low forecast for the city you work in, on each day of the calendar.")
                    }

                    // 5. Pay day
                    Section {
                        NavigationLink {
                            PaySetupView(showsSkip: false) {
                                // Stay on Settings after saving; sync happens inside PaySetupView.
                            }
                        } label: {
                            HStack {
                                row("Payday", "dollarsign.circle")
                                Spacer()
                                Text(payPreferencesSummary)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    } header: {
                        Text("Pay")
                    } footer: {
                        Text("Direct Deposit paydays are marked on Home and added as all-day events on your Work Schedule calendar.")
                    }

                    // 5b. CS Supervisor → Keys
                    Section {
                        if keysUnlocked {
                            HStack {
                                row("Keys access", "key.fill")
                                Spacer()
                                Text("Unlocked")
                                    .foregroundStyle(.secondary)
                            }
                            Button(role: .destructive) {
                                CSSupAccess.revokeKeysAccess()
                                keysUnlocked = false
                            } label: {
                                row("Lock Keys tab", "lock.fill", tint: .red)
                            }
                        } else {
                            Button {
                                csPasscodeDraft = ""
                                csPasscodeError = false
                                showingCSPasscode = true
                            } label: {
                                row("Unlock Keys (CS Sup)", "key.fill")
                            }
                        }
                    } header: {
                        Text("CS Supervisor")
                    } footer: {
                        Text("CS Supervisors can unlock the Keys tab for safe codes and liquor case. Content for Keys is coming soon.")
                    }

                    // 6. Calendar & Display
                    Section {
                        Toggle(isOn: $calendarDayTickerMode) {
                            row("Day ticker & continuous scroll", "calendar.day.timeline.leading")
                        }
                        .tint(theme.current.toggleTint)
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
                        .tint(theme.current.readableAccent)
                        .id(theme.highContrast)
                    } header: {
                        Text("Display & Calendar")
                    } footer: {
                        Text("Day ticker shows a compact horizontal day strip and lets you continuously scroll vertically through past and upcoming days.")
                    }

                    // 5. Tools & Quick Actions
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
                        Text("Plan break schedules or track shift duties and checklists.")
                    }

                    // 6. Widgets & Lock Screen
                    Section {
                        WidgetShowcase()
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    } header: {
                        Text("Widgets")
                    } footer: {
                        Text("Add Next Shift or Discount Barcode to your Home Screen or Lock Screen.")
                    }

                    // 7. About & Help
                    Section {
                        Button {
                            showingOnboarding = true
                        } label: {
                            row("Redo setup", "list.bullet.clipboard")
                        }
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
                        Toggle(isOn: demoBinding) {
                            row("Demo mode", "sparkles")
                        }
                        .tint(theme.current.toggleTint)

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
                    } footer: {
                        if demoMode {
                            Text("Demo mode is currently active with sample data.")
                        }
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
            .onAppear {
                appearanceMode = colorScheme
            }
            .onChange(of: colorScheme) { _, newScheme in
                appearanceMode = newScheme
            }
            .sheet(isPresented: $showingCredentialForm) {
                AutoSignInCredentialForm()
            }
            .sheet(isPresented: $showingSignIn) {
                LoginView()
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
                WelcomeView(buttonTitle: "Done", asksPaySetup: false) { showingWelcome = false }
            }
            .fullScreenCover(isPresented: $showingOnboarding) {
                OnboardingWizardView {
                    showingOnboarding = false
                }
            }
            .sheet(isPresented: $showingCSPasscode) {
                NavigationStack {
                    Form {
                        Section {
                            SecureField("Passcode", text: $csPasscodeDraft)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            if csPasscodeError {
                                Text("That passcode didn’t work. Try again.")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        } footer: {
                            Text("Enter the CS Supervisor passcode to show the Keys tab.")
                        }
                    }
                    .navigationTitle("Unlock Keys")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showingCSPasscode = false
                                csPasscodeDraft = ""
                                csPasscodeError = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Unlock") {
                                if CSSupAccess.unlock(with: csPasscodeDraft) {
                                    keysUnlocked = true
                                    showingCSPasscode = false
                                    csPasscodeDraft = ""
                                    csPasscodeError = false
                                } else {
                                    csPasscodeError = true
                                }
                            }
                            .disabled(csPasscodeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }

    /// A settings row: a small tinted icon tile beside the title. Tile colors
    /// come from the selected theme's palette so neighbouring rows stay
    /// distinct without leaving that theme's family.
    private func row(_ title: LocalizedStringKey, _ symbol: String, tint: Color? = nil, verbatim: Bool = false) -> some View {
        Label {
            if verbatim { Text(verbatim: "WF Icon") } else { Text(title) }
        } icon: {
            ThemedGlyph(symbol: symbol, tint: tint)
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
    var scheme: ColorScheme = .dark
    @ObservedObject private var theme = ThemeManager.shared

    private let columns = Array(repeating: GridItem(.flexible()), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(AppColorThemes.all) { item in
                Button {
                    theme.setSelectedTheme(item, for: scheme)
                } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .fill(item.accent)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: theme.selectedTheme(for: scheme).id == item.id ? 2.5 : 0)
                            )
                            .shadow(color: item.accent.opacity(0.35), radius: 4, y: 2)

                        Text(LocalizedStringKey(item.name))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(theme.selectedTheme(for: scheme).id == item.id ? Color.primary : .secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(theme.selectedTheme(for: scheme).id == item.id ? Color.primary.opacity(0.08) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }
}

/// Email/password Supabase backup — create account, sign in, backup, restore.
private struct CloudBackupSettingsView: View {
    @State private var backup = SupabaseBackupService.shared
    @State private var email = ""
    @State private var password = ""
    @State private var errorText: String?
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Form {
            if !SupabaseConfig.isConfigured {
                Section {
                    Label(
                        "Add your Supabase project URL and anon key in SupabaseConfig.swift, then run store/supabase-shifts.sql in the SQL editor.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                }
            } else if backup.isSignedIn {
                Section {
                    LabeledContent("Account") {
                        Text(backup.email ?? "—")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Last backup") {
                        Text(backup.lastBackupAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Signed in")
                }

                Section {
                    Button {
                        Task { await run { try await backup.backupNow() } }
                    } label: {
                        Label("Backup now", systemImage: "icloud.and.arrow.up")
                    }
                    .disabled(backup.isBusy)

                    Button {
                        Task { await run { try await backup.restoreAndMerge() } }
                    } label: {
                        Label("Restore from backup", systemImage: "icloud.and.arrow.down")
                    }
                    .disabled(backup.isBusy)

                    Button("Sign out", role: .destructive) {
                        backup.signOut()
                        errorText = nil
                    }
                }

                if let status = backup.statusMessage {
                    Section {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("Cloud account")
                } footer: {
                    Text("Creates a private backup of your shifts. Not your Whole Foods / Amazon login.")
                }

                Section {
                    Button {
                        Task { await run { try await backup.signIn(email: email, password: password) } }
                    } label: {
                        Label("Sign in", systemImage: "person.crop.circle")
                    }
                    .disabled(!canSubmit || backup.isBusy)

                    Button {
                        Task { await run { try await backup.signUp(email: email, password: password) } }
                    } label: {
                        Label("Create account", systemImage: "person.crop.circle.badge.plus")
                    }
                    .disabled(!canSubmit || backup.isBusy)
                }
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Cloud Backup")
        .navigationBarTitleDisplayMode(.inline)
        .tint(theme.current.readableAccent)
        .onAppear {
            if let existing = backup.email, email.isEmpty {
                email = existing
            }
        }
    }

    private var canSubmit: Bool {
        email.contains("@") && password.count >= 6
    }

    private func run(_ work: @escaping () async throws -> Void) async {
        errorText = nil
        do {
            try await work()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// Six-preview Appearance picker: Classic, Light, and Dark for Light Mode and
/// for Dark Mode, matching the phone-mockup layout used by Fantastical.
private struct AppearanceSettingsView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private let selectionBlue = Color(red: 0.0, green: 0.48, blue: 1.0)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                appearanceGroup(
                    title: colorScheme == .light ? "Light Mode (Currently Active)" : "Light Mode",
                    scheme: .light,
                    cardFill: Color.white,
                    labelColor: Color(red: 0.35, green: 0.35, blue: 0.38),
                    selectedLabelColor: Color(red: 0.08, green: 0.08, blue: 0.10)
                )

                appearanceGroup(
                    title: colorScheme == .dark ? "Dark Mode (Currently Active)" : "Dark Mode",
                    scheme: .dark,
                    cardFill: Color(red: 0.17, green: 0.17, blue: 0.18),
                    labelColor: Color(white: 0.62),
                    selectedLabelColor: Color.white
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func appearanceGroup(
        title: LocalizedStringKey,
        scheme: ColorScheme,
        cardFill: Color,
        labelColor: Color,
        selectedLabelColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.secondary)
                .padding(.horizontal, 4)

            HStack(alignment: .top, spacing: 0) {
                ForEach(CalendarDisplayStyle.allCases) { style in
                    let selected = theme.displayStyle(for: scheme) == style
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            theme.setDisplayStyle(style, for: scheme)
                        }
                    } label: {
                        VStack(spacing: 10) {
                            CalendarStylePhonePreview(style: style, selected: selected, ring: selectionBlue)
                            Text(style.name)
                                .font(.subheadline.weight(selected ? .semibold : .regular))
                                .foregroundStyle(selected ? selectedLabelColor : labelColor)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 16)
            .background(cardFill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
    }
}

/// Mini phone used in the Appearance picker. Classic is the mixed white+dark
/// calendar, Light is all white, Dark is all dark.
private struct CalendarStylePhonePreview: View {
    let style: CalendarDisplayStyle
    let selected: Bool
    let ring: Color

    private var deviceFill: Color {
        style.usesLightDeviceChrome ? Color(white: 0.97) : Color(white: 0.08)
    }

    private var islandFill: Color {
        style.usesLightDeviceChrome ? Color.black : Color(white: 0.22)
    }

    private var contentFill: Color {
        style.agendaIsDark ? Color(white: 0.10) : Color.white
    }

    private var lineFill: Color {
        style.agendaIsDark ? Color(white: 0.32) : Color(white: 0.82)
    }

    private let eventDots: [Color] = [
        Color(red: 0.20, green: 0.48, blue: 1.0),
        Color(red: 0.20, green: 0.78, blue: 0.42),
        Color(red: 1.00, green: 0.62, blue: 0.16),
        Color(red: 0.95, green: 0.32, blue: 0.55),
        Color(red: 0.55, green: 0.38, blue: 0.95)
    ]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(deviceFill)
                .shadow(color: .black.opacity(style.usesLightDeviceChrome ? 0.08 : 0.35), radius: 3, y: 1)

            VStack(spacing: 6) {
                Capsule()
                    .fill(islandFill)
                    .frame(width: 26, height: 7)
                    .padding(.top, 8)

                HStack(spacing: 5) {
                    Circle().fill(Color(red: 0.20, green: 0.48, blue: 1.0)).frame(width: 8, height: 8)
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(style.agendaIsDark ? Color(white: 0.28) : Color(white: 0.86)).frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 2)

                VStack(spacing: 6) {
                    ForEach(0..<5, id: \.self) { index in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(eventDots[index % eventDots.count])
                                .frame(width: 6, height: 6)
                            Capsule()
                                .fill(lineFill)
                                .frame(height: 3.5)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(contentFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 7)

                Spacer(minLength: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(selected ? ring : Color.clear, lineWidth: 3.5)
        }
        .frame(width: 86, height: 148)
    }
}

/// Entry for the TM ID. It's typed into a secure field, saved to the Keychain
/// (and pushed to widgets), and from then on only ever shown as
/// "*****" — with a barcode preview matching the official Whole Foods discount card.
private struct TMIDField: View {
    @State private var isStored = false
    @State private var tmIDValue: String?
    @State private var isEditing = false
    @State private var draft = ""
    @State private var showingDiscountCardModal = false

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func refresh() {
        let id = BarcodeStore.value
        isStored = id != nil
        tmIDValue = id
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

    @ViewBuilder
    private var preview: some View {
        if let id = tmIDValue {
            Button {
                showingDiscountCardModal = true
            } label: {
                VStack(spacing: 8) {
                    UPCABarcodeCard(input: id)
                        .padding(.vertical, 16)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)

                    HStack(spacing: 5) {
                        Image(systemName: "viewfinder")
                            .font(.caption.bold())
                        Text("Tap for full-screen card & max brightness")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingDiscountCardModal) {
                DiscountCardModalView(tmID: id)
            }
        }
    }
}

struct DiscountCardModalView: View {
    let tmID: String
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @State private var previousBrightness: CGFloat = 0.5

    private var currentScreen: UIScreen? {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .screen)
            ?? (UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?
                .screen)
    }
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 4) {
                        Text("Enrique Martin")
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text("Whole Foods Market Team Member")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 20)

                    VStack(spacing: 0) {
                        UPCABarcodeCard(input: tmID)
                            .padding(.vertical, 22)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity)
                            .frame(height: 220)
                    }
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    .padding(.horizontal, 16)

                    VStack(spacing: 12) {
                        Text("Please open an ASK TMS case or call 833-4ASKTMS (833-427-5867) to report the problem.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Text("This electronic discount card is for the sole use of the Whole Foods Market Team Member named above. Additional picture identification may be requested. Misuse of the discount card, including electronic duplication, is strictly prohibited. This card is the sole property of Whole Foods Market and use of it is governed by the discount policy in the GIG.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .padding(.bottom, 32)
            }
            .navigationTitle("Discount Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            #if os(iOS)
            if let screen = currentScreen {
                previousBrightness = screen.brightness
                screen.brightness = 1.0
            }
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
        }
        .onDisappear {
            #if os(iOS)
            if let screen = currentScreen {
                screen.brightness = previousBrightness
            }
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
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

/// Search for the city the associate works in. Results come from Open-Meteo geocoding.
private struct WorkCityPicker: View {
    @ObservedObject private var weather = WorkWeatherStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [WorkCity] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var isSearching = false

    var body: some View {
        List {
            if let city = weather.city {
                Section("Current") {
                    Button {
                        weather.setCity(nil)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(city.displayName)
                                    .foregroundStyle(Color.primary)
                                if !city.country.isEmpty {
                                    Text(city.country)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("Clear")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            Section {
                if isSearching && results.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Searching…")
                            .foregroundStyle(.secondary)
                    }
                } else if results.isEmpty && query.trimmingCharacters(in: .whitespaces).count >= 2 {
                    Text("No matching cities")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(results) { city in
                        Button {
                            weather.setCity(city)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(city.displayName)
                                    .foregroundStyle(Color.primary)
                                if !city.country.isEmpty {
                                    Text(city.country)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } header: {
                if weather.city == nil {
                    Text("Search for the city you work in")
                }
            }
        }
        .navigationTitle("Work City")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "City name")
        .onChange(of: query) { _, newValue in
            searchTask?.cancel()
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 else {
                results = []
                isSearching = false
                return
            }
            isSearching = true
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                let found = await weather.searchCities(trimmed)
                guard !Task.isCancelled else { return }
                results = found
                isSearching = false
            }
        }
    }
}
