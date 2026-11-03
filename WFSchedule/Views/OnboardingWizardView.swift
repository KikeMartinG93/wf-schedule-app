import SwiftUI

/// First-launch (and Settings redo) setup: language, TM ID, work city, theme,
/// font, contrast, payday, and optional CS Sup → Keys unlock.
struct OnboardingWizardView: View {
    var onFinished: () -> Void

    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var weather = WorkWeatherStore.shared
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.system.rawValue
    @AppStorage(FontPreference.key, store: FontPreference.store) private var roundedFont = true

    @State private var step: Step = .intro
    @State private var tmIDDraft = ""
    @State private var cityQuery = ""
    @State private var cityResults: [WorkCity] = []
    @State private var citySearchTask: Task<Void, Never>?
    @State private var isSearchingCity = false
    @State private var payMethod: PaymentMethod?
    @State private var payWeekday: PaydayWeekday?
    @State private var isCSSup: Bool?
    @State private var passcodeDraft = ""
    @State private var passcodeError = false

    private enum Step: Int, CaseIterable {
        case intro
        case language
        case tmID
        case workCity
        case theme
        case font
        case contrast
        case payMethod
        case payWeekday
        case csSup
        case csPasscode
    }

    private var canAdvance: Bool {
        switch step {
        case .intro, .language, .theme, .font, .contrast:
            true
        case .tmID:
            true // skippable
        case .workCity:
            true // skippable
        case .payMethod:
            payMethod != nil
        case .payWeekday:
            payWeekday != nil
        case .csSup:
            isCSSup != nil
        case .csPasscode:
            !passcodeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            progressBar
                .padding(.horizontal, 28)
                .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    stepBody
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)

            bottomBar
        }
        .interactiveDismissDisabled()
        .onAppear {
            if let existing = BarcodeStore.value, DemoMode.isEnabled == false {
                tmIDDraft = existing
            }
            payMethod = PayPreferences.method
            payWeekday = PayPreferences.weekday
            if CSSupAccess.hasAnswered {
                isCSSup = CSSupAccess.isCSSup
            }
        }
    }

    // MARK: - Chrome

    private var progressBar: some View {
        GeometryReader { geo in
            let fraction = CGFloat(step.rawValue + 1) / CGFloat(Step.allCases.count)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(theme.current.readableAccent)
                    .frame(width: max(8, geo.size.width * fraction))
            }
        }
        .frame(height: 4)
        .accessibilityLabel("Setup progress")
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.largeTitle.weight(.bold))
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: LocalizedStringKey {
        switch step {
        case .intro: "Welcome to WF Schedule"
        case .language: "Language"
        case .tmID: "Your TM ID"
        case .workCity: "Where do you work?"
        case .theme: "Pick a color"
        case .font: "Font style"
        case .contrast: "Contrast"
        case .payMethod: "How do you get paid?"
        case .payWeekday: "When is Direct Deposit?"
        case .csSup: "Are you a CS Supervisor?"
        case .csPasscode: "Enter your passcode"
        }
    }

    private var subtitle: LocalizedStringKey? {
        switch step {
        case .intro:
            "Here’s what WF Schedule does — then a few quick questions to personalize it."
        case .language:
            "You can change this anytime in Settings."
        case .tmID:
            "Powers your discount barcode and widgets. Stored in the Keychain on this device."
        case .workCity:
            "Home shows the high/low forecast for your work city."
        case .theme:
            "The whole app follows this palette. You can fine-tune Light and Dark later in Settings."
        case .font:
            "Rounded is the default. Regular uses the standard system font."
        case .contrast:
            "High contrast turns the app, widgets, and Live Activity black, white, and gray."
        case .payMethod:
            "We’ll mark Payday on your schedule if you use Direct Deposit."
        case .payWeekday:
            "Whole Foods Direct Deposit is every other week. Pick the day yours lands."
        case .csSup:
            "CS Supervisors can unlock the Keys tab for safe codes and liquor case access."
        case .csPasscode:
            "Ask a CS Supervisor for the store passcode if you don’t have it."
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Button(action: advance) {
                Text(primaryTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(theme.current.buttonFill)
            .controlSize(.large)
            .disabled(!canAdvance)

            if showsSecondary {
                Button(secondaryTitle, action: secondaryAction)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.current.readableAccent)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var primaryTitle: LocalizedStringKey {
        switch step {
        case .intro: "Get started"
        case .csPasscode: "Unlock Keys"
        case .csSup where isCSSup == false: "Done"
        default: "Continue"
        }
    }

    private var showsSecondary: Bool { true }

    private var secondaryTitle: LocalizedStringKey {
        switch step {
        case .intro: "Explore Demo Mode"
        case .tmID, .workCity, .payMethod: "Skip for now"
        default: "Back"
        }
    }

    private func secondaryAction() {
        switch step {
        case .intro:
            DemoMode.set(true)
            finishWizard(markPaySkipped: true)
        case .tmID, .workCity:
            goForward()
        case .payMethod:
            PayPreferences.markSkipped()
            goForward(fromPaySkip: true)
        case .payWeekday:
            withAnimation { step = .payMethod }
        case .csPasscode:
            passcodeError = false
            passcodeDraft = ""
            withAnimation { step = .csSup }
        default:
            goBack()
        }
    }

    // MARK: - Step bodies

    @ViewBuilder
    private var stepBody: some View {
        switch step {
        case .intro:
            introFeatures
        case .language:
            VStack(spacing: 12) {
                ForEach(AppLanguage.allCases) { option in
                    choiceCard(
                        title: languageTitle(option),
                        detail: languageDetail(option),
                        symbol: "globe",
                        selected: languageRaw == option.rawValue
                    ) {
                        languageRaw = option.rawValue
                        AppLanguage.apply(option)
                    }
                }
            }
        case .tmID:
            VStack(alignment: .leading, spacing: 14) {
                SecureField("TM ID", text: $tmIDDraft)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.numberPad)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                Text("Usually 7 digits. Used only for your discount barcode.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .workCity:
            workCityBody
        case .theme:
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(AppColorThemes.all) { item in
                    Button {
                        theme.setSelectedTheme(item, for: .light)
                        theme.setSelectedTheme(item, for: .dark)
                    } label: {
                        VStack(spacing: 8) {
                            Circle()
                                .fill(item.accent)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white, lineWidth: theme.current.id == item.id ? 2.5 : 0)
                                )
                            Text(LocalizedStringKey(item.name))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(theme.current.id == item.id ? Color.primary : .secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(theme.current.id == item.id
                                      ? theme.current.readableAccent.opacity(0.12)
                                      : Color.primary.opacity(0.04))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(theme.highContrast)
                }
            }
            if theme.highContrast {
                Text("Turn off High contrast later in Settings to see colors.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .font:
            VStack(spacing: 12) {
                choiceCard(
                    title: "Rounded",
                    detail: "Softer system rounded type — the app default.",
                    symbol: "textformat",
                    selected: roundedFont
                ) { roundedFont = true }
                choiceCard(
                    title: "Regular",
                    detail: "Standard system font.",
                    symbol: "textformat.size",
                    selected: !roundedFont
                ) { roundedFont = false }
            }
        case .contrast:
            VStack(spacing: 12) {
                choiceCard(
                    title: "Regular",
                    detail: "Full color themes.",
                    symbol: "paintpalette.fill",
                    selected: !theme.highContrast
                ) { theme.highContrast = false }
                choiceCard(
                    title: "High contrast",
                    detail: "Black, white, and gray only — including widgets.",
                    symbol: "circle.lefthalf.filled",
                    selected: theme.highContrast
                ) { theme.highContrast = true }
            }
        case .payMethod:
            VStack(spacing: 12) {
                ForEach(PaymentMethod.allCases) { option in
                    choiceCard(
                        title: option.title,
                        detail: option == .directDeposit
                            ? String(localized: "Paid every other week by bank deposit.")
                            : String(localized: "Paid by paper check — no payday markers."),
                        symbol: option == .directDeposit ? "building.columns.fill" : "doc.text.fill",
                        selected: payMethod == option
                    ) { payMethod = option }
                }
            }
        case .payWeekday:
            VStack(spacing: 12) {
                ForEach(PaydayWeekday.allCases) { option in
                    let next = option.anchorPayday
                    let period = PaydayCalendar.periodDescription(forPayday: next) ?? ""
                    let nextLabel = next.formatted(.dateTime.month(.abbreviated).day().year())
                    choiceCard(
                        title: option.title,
                        detail: "Next payday \(nextLabel) · period \(period)",
                        symbol: "calendar.badge.clock",
                        selected: payWeekday == option
                    ) { payWeekday = option }
                }
            }
        case .csSup:
            VStack(spacing: 12) {
                choiceCard(
                    title: "Yes",
                    detail: "I’ll unlock the Keys tab with a passcode.",
                    symbol: "person.badge.shield.checkmark.fill",
                    selected: isCSSup == true
                ) { isCSSup = true }
                choiceCard(
                    title: "No",
                    detail: "Skip Keys — you can change this later in Settings.",
                    symbol: "person.fill",
                    selected: isCSSup == false
                ) { isCSSup = false }
            }
        case .csPasscode:
            VStack(alignment: .leading, spacing: 14) {
                SecureField("Passcode", text: $passcodeDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .onChange(of: passcodeDraft) { _, _ in passcodeError = false }
                if passcodeError {
                    Text("That passcode didn’t work. Try again.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var introFeatures: some View {
        VStack(alignment: .leading, spacing: 18) {
            introRow(
                "calendar",
                "Your schedule, always current",
                "Sign in with UKG once and your shifts sync in the background — month calendar or a simple list."
            )
            introRow(
                "bell.badge.fill",
                "Know the moment it changes",
                "Get notified when a shift is added, moved, or removed, plus a reminder before each one starts."
            )
            introRow(
                "calendar.badge.plus",
                "Lives in Apple Calendar",
                "Shifts appear in their own Work Schedule calendar on all your Apple devices."
            )
            introRow(
                "barcode",
                "Discount barcode at hand",
                "Save your TM ID to show your discount card and Lock Screen / Home Screen widgets instantly."
            )
            introRow(
                "cup.and.saucer.fill",
                "Breaks that stay with you",
                "Start a break or lunch and watch the countdown on the Lock Screen and Dynamic Island."
            )
            introRow(
                "dollarsign.circle.fill",
                "Payday on your calendar",
                "Direct Deposit on Wednesdays or Fridays adds biweekly Payday markers on Home and Apple Calendar."
            )
            introRow(
                "building.2.fill",
                "Weather where you work",
                "Pick your work city and Home shows the high/low on each day of the agenda."
            )
            introRow(
                "paintpalette.fill",
                "Make it yours",
                "Color theme, rounded or regular font, high contrast, and language — all set in the next steps."
            )
            introRow(
                "lock.rectangle.stack.fill",
                "Next shift at a glance",
                "Add the Next Shift widget to your Lock Screen to see what’s coming and how long until it starts."
            )
        }
    }

    private func introRow(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ThemedGlyph(symbol: symbol, size: 36, font: .body.weight(.semibold))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var workCityBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let city = weather.city {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(city.displayName)
                            .font(.headline)
                        if !city.country.isEmpty {
                            Text(city.country)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Clear") { weather.setCity(nil) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(theme.current.readableAccent.opacity(0.12))
                )
            }

            TextField("Search city", text: $cityQuery)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
                .onChange(of: cityQuery) { _, newValue in
                    citySearchTask?.cancel()
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.count >= 2 else {
                        cityResults = []
                        isSearchingCity = false
                        return
                    }
                    isSearchingCity = true
                    citySearchTask = Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled else { return }
                        let found = await weather.searchCities(trimmed)
                        guard !Task.isCancelled else { return }
                        cityResults = found
                        isSearchingCity = false
                    }
                }

            if isSearchingCity && cityResults.isEmpty {
                HStack {
                    ProgressView()
                    Text("Searching…")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(cityResults) { city in
                    Button {
                        weather.setCity(city)
                        cityQuery = ""
                        cityResults = []
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(city.displayName)
                                .font(.headline)
                                .foregroundStyle(Color.primary)
                            if !city.country.isEmpty {
                                Text(city.country)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Navigation

    private func advance() {
        switch step {
        case .intro:
            goForward()
        case .language:
            goForward()
        case .tmID:
            let trimmed = tmIDDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                BarcodeStore.value = trimmed
            }
            goForward()
        case .workCity:
            goForward()
        case .theme, .font, .contrast:
            goForward()
        case .payMethod:
            guard let payMethod else { return }
            if payMethod == .check {
                PayPreferences.save(method: .check, weekday: nil)
                Task { try? CalendarSyncService().syncPaydayEvents() }
                withAnimation { step = .csSup }
            } else {
                withAnimation { step = .payWeekday }
            }
        case .payWeekday:
            guard let payWeekday else { return }
            PayPreferences.save(method: .directDeposit, weekday: payWeekday)
            Task {
                let sync = CalendarSyncService()
                try? await sync.requestAccess()
                try? sync.syncPaydayEvents()
            }
            withAnimation { step = .csSup }
        case .csSup:
            guard let isCSSup else { return }
            CSSupAccess.saveAnswer(isCSSup: isCSSup)
            if isCSSup {
                withAnimation { step = .csPasscode }
            } else {
                finishWizard(markPaySkipped: false)
            }
        case .csPasscode:
            if CSSupAccess.unlock(with: passcodeDraft) {
                finishWizard(markPaySkipped: false)
            } else {
                passcodeError = true
            }
        }
    }

    private func goForward(fromPaySkip: Bool = false) {
        withAnimation {
            switch step {
            case .intro: step = .language
            case .language: step = .tmID
            case .tmID: step = .workCity
            case .workCity: step = .theme
            case .theme: step = .font
            case .font: step = .contrast
            case .contrast: step = .payMethod
            case .payMethod:
                if fromPaySkip {
                    step = .csSup
                } else if payMethod == .directDeposit {
                    step = .payWeekday
                } else {
                    step = .csSup
                }
            case .payWeekday: step = .csSup
            case .csSup: step = isCSSup == true ? .csPasscode : step
            case .csPasscode: break
            }
        }
    }

    private func goBack() {
        withAnimation {
            switch step {
            case .intro: break
            case .language: step = .intro
            case .tmID: step = .language
            case .workCity: step = .tmID
            case .theme: step = .workCity
            case .font: step = .theme
            case .contrast: step = .font
            case .payMethod: step = .contrast
            case .payWeekday: step = .payMethod
            case .csSup:
                if payMethod == .directDeposit && PayPreferences.weekday != nil {
                    step = .payWeekday
                } else {
                    step = .payMethod
                }
            case .csPasscode: step = .csSup
            }
        }
    }

    private func finishWizard(markPaySkipped: Bool) {
        if markPaySkipped && !PayPreferences.isConfigured {
            PayPreferences.markSkipped()
        }
        if !CSSupAccess.hasAnswered {
            CSSupAccess.saveAnswer(isCSSup: false)
        }
        onFinished()
    }

    // MARK: - Helpers

    private func languageTitle(_ language: AppLanguage) -> LocalizedStringKey {
        switch language {
        case .system: "System default"
        case .en: "English"
        case .es: "Español"
        }
    }

    private func languageDetail(_ language: AppLanguage) -> String {
        switch language {
        case .system: String(localized: "Follow the language on this iPhone.")
        case .en: "English"
        case .es: "Español"
        }
    }

    private func choiceCard(
        title: LocalizedStringKey,
        detail: String,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                ThemedGlyph(symbol: symbol, size: 36, font: .body.weight(.semibold))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? theme.current.readableAccent : Color.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? theme.current.readableAccent.opacity(0.12) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? theme.current.readableAccent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
