import SwiftUI

/// Change history for the schedule: every new, changed, or removed shift ever
/// detected by a sync, newest first. UKG's data can't tell us "this was a
/// swap, and with whom" — so each row has an optional free-text field for the
/// user to fill that in themselves when they know it.
///
/// Unseen entries are shown in full above a collapsible "Viewed" section.
/// Nothing has to be tapped to acknowledge them: they're already showing
/// their full detail the moment this tab is open, and leaving the tab (see
/// `isActive`) quietly marks whatever was showing as seen — the same "read
/// on leaving the list" behavior as Mail or Messages. "Mark all as viewed"
/// is still there for clearing the badge without switching tabs.
struct AlertsView: View {
    /// Whether this is the currently-selected tab. TabView keeps every tab's
    /// view alive rather than tearing it down on switch (see `AppTheme`'s
    /// `BackgroundPulse` for the same fact biting a different feature), so
    /// `onDisappear` can't be trusted to fire on tab switches — this, passed
    /// down from `MainTabView`'s own `selectedTab`, is what actually does.
    var isActive: Bool = true
    @State private var entries: [ChangeLogEntry] = ChangeLogStore.shared.load()
    @State private var isViewedSectionExpanded = false

    private var unseenEntries: [ChangeLogEntry] { entries.filter { !$0.seen } }
    private var seenEntries: [ChangeLogEntry] { entries.filter { $0.seen } }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                Group {
                    if entries.isEmpty {
                        ContentUnavailableView(
                            "No changes yet",
                            systemImage: "bell",
                            description: Text("New, changed, or removed shifts will show up here after your next sync.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                if unseenEntries.isEmpty {
                                    Text("You're all caught up")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 24)
                                } else {
                                    ForEach(Array(unseenEntries.enumerated()), id: \.element.id) { index, entry in
                                        ChangeLogRow(entry: entry) { note in
                                            ChangeLogStore.shared.updateNote(id: entry.id, note: note)
                                            entries = ChangeLogStore.shared.load()
                                        }
                                        if index < unseenEntries.count - 1 {
                                            Divider()
                                        }
                                    }
                                }

                                if !seenEntries.isEmpty {
                                    viewedSection
                                }

                                Color.clear.frame(height: 40)
                            }
                            .padding(.horizontal)
                            .padding(.top, 4)
                        }
                        // Nothing to scroll (or bounce) when it all fits — otherwise
                        // dragging it moves the tab bar and shift bar out of step.
                        .scrollBounceBehavior(.basedOnSize)
                    }
                }
                // Same as Settings and Breaks: the title is a top bar the content
                // scrolls under, fading out softly instead of a hard cut-off.
                .safeAreaBar(edge: .top) {
                    header
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                entries = ChangeLogStore.shared.load()
            }
            .onReceive(NotificationCenter.default.publisher(for: ScheduleStore.didChangeNotification)) { _ in
                entries = ChangeLogStore.shared.load()
            }
            .onChange(of: isActive) { wasActive, active in
                if wasActive && !active {
                    markAllSeenQuietly()
                }
            }
        }
    }

    /// The automatic version of "Mark all as viewed" — fires when the user
    /// switches away from this tab, not on a button tap. No animation: the
    /// tab isn't on screen to see one, and the next time it's opened the
    /// list should just already read as caught up.
    private func markAllSeenQuietly() {
        guard entries.contains(where: { !$0.seen }) else { return }
        ChangeLogStore.shared.markAllSeen()
        entries = ChangeLogStore.shared.load()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Alerts")
                .font(.largeTitle.bold())
                .foregroundStyle(Color(uiColor: .label))
            Spacer()
            if !unseenEntries.isEmpty {
                Button("Mark all as viewed") {
                    ChangeLogStore.shared.markAllSeen()
                    entries = ChangeLogStore.shared.load()
                }
                .font(.subheadline)
            }
        }
    }

    /// Collapsed by default — past, already-acknowledged alerts shouldn't
    /// compete for attention with anything still unseen.
    private var viewedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isViewedSectionExpanded.toggle()
                }
            } label: {
                HStack {
                    Text("Viewed (\(seenEntries.count))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isViewedSectionExpanded ? 90 : 0))
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isViewedSectionExpanded {
                ForEach(Array(seenEntries.enumerated()), id: \.element.id) { index, entry in
                    ChangeLogRow(entry: entry) { note in
                        ChangeLogStore.shared.updateNote(id: entry.id, note: note)
                        entries = ChangeLogStore.shared.load()
                    }
                    if index < seenEntries.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding(.top, unseenEntries.isEmpty ? 0 : 8)
    }
}

private struct ChangeLogRow: View {
    let entry: ChangeLogEntry
    var onNoteChanged: (String) -> Void

    @State private var noteText: String
    /// A removed shift is the closest thing to a real "swap" signal this data
    /// has — a shift you had is just gone, plausibly because someone covered
    /// it. New/changed shifts have no such implication, so the note field
    /// stays tucked away for those unless the user explicitly asks for it by
    /// tapping "Add note".
    @State private var isNoteExpanded: Bool
    /// Seen entries (shown inside the collapsible "Viewed" section) default
    /// to a compact one-line layout, but stay tappable back open — "viewed"
    /// isn't "gone," just quieter. Unseen entries always show in full.
    @State private var isExpanded: Bool
    @FocusState private var noteFocused: Bool
    @ObservedObject private var theme = ThemeManager.shared

    init(entry: ChangeLogEntry, onNoteChanged: @escaping (String) -> Void) {
        self.entry = entry
        self.onNoteChanged = onNoteChanged
        _noteText = State(initialValue: entry.swapNote ?? "")
        _isNoteExpanded = State(initialValue: entry.kind == .removed || entry.swapNote?.isEmpty == false)
        _isExpanded = State(initialValue: !entry.seen)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(kindColor)
                .frame(width: 4)
                .clipShape(.rect(cornerRadius: 2))

            if isExpanded {
                fullDetail
            } else {
                compactSummary
            }
        }
        .padding(.vertical, isExpanded ? 12 : 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if entry.seen {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            }
        }
    }

    private var fullDetail: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(kindLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(kindTextColor)
                Spacer()
                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("\(entry.shift.job) — \(entry.shift.startTime.formatted(date: .abbreviated, time: .omitted))")
                .font(.headline)

            Text(entry.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if isNoteExpanded {
                HStack(spacing: 6) {
                    Image(systemName: "person.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Swapped with? (optional)", text: $noteText)
                        .font(.subheadline)
                        .focused($noteFocused)
                }
                .padding(.top, 2)
                .onChange(of: noteFocused) { wasFocused, isFocused in
                    if wasFocused && !isFocused {
                        onNoteChanged(noteText)
                    }
                }
            } else {
                Button("Add note") {
                    isNoteExpanded = true
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }
        }
    }

    /// One line: kind color already carries most of the meaning via the bar
    /// on the left, so this only needs the job, the date, and a quiet
    /// confirmation it's been seen.
    private var compactSummary: some View {
        HStack(spacing: 8) {
            Text(entry.shift.job)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(entry.timestamp.formatted(date: .numeric, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: "checkmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var kindLabel: LocalizedStringKey {
        switch entry.kind {
        case .new: "NEW SHIFT"
        case .changed: "SHIFT CHANGED"
        case .removed: "SHIFT REMOVED"
        }
    }

    private var kindColor: Color {
        switch entry.kind {
        case .new: Color.readable(theme.current.accent, minimumContrast: 3)
        case .changed: theme.highContrast ? Color(.systemGray) : Color.readable(.orange, minimumContrast: 3)
        case .removed: theme.highContrast ? Color(.label) : Color.readable(.red, minimumContrast: 3)
        }
    }

    /// Text-safe (4.5:1) version of `kindColor` for the label.
    private var kindTextColor: Color {
        switch entry.kind {
        case .new: theme.current.readableAccent
        case .changed: theme.highContrast ? Color.primary : Color.readable(.orange)
        case .removed: theme.highContrast ? Color.primary : Color.readable(.red)
        }
    }
}
