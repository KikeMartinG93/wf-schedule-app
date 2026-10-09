import SwiftUI

enum AlertsFilter: Int, CaseIterable {
    case unread = 0
    case history30 = 30
    case history60 = 60
    case history90 = 90

    var next: AlertsFilter {
        switch self {
        case .unread: return .history30
        case .history30: return .history60
        case .history60: return .history90
        case .history90: return .unread
        }
    }
}

/// Change history for the schedule: every new, changed, or removed shift ever
/// detected by a sync, newest first.
struct AlertsView: View {
    var isActive: Bool = true
    @Binding var filter: AlertsFilter
    @State private var entries: [ChangeLogEntry] = ChangeLogStore.shared.load()

    init(isActive: Bool = true, filter: Binding<AlertsFilter> = .constant(.unread)) {
        self.isActive = isActive
        self._filter = filter
    }

    private var displayedEntries: [ChangeLogEntry] {
        let now = Date()
        let cutoff30 = now.addingTimeInterval(-30 * 86_400)
        let cutoff60 = now.addingTimeInterval(-60 * 86_400)
        let cutoff90 = now.addingTimeInterval(-90 * 86_400)

        switch filter {
        case .unread:
            // Unread (all unread)
            return entries.filter { !$0.seen }
        case .history30:
            // Last 30 days (Last 30 days read)
            return entries.filter { $0.seen && $0.timestamp >= cutoff30 }
        case .history60:
            // Last 60 days (Last 60 days - anything already displayed on 30 days)
            return entries.filter { $0.seen && $0.timestamp >= cutoff60 && $0.timestamp < cutoff30 }
        case .history90:
            // Last 90 days (Last 90 days minus anything already displayed on 60 and/or 30 days)
            return entries.filter { $0.seen && $0.timestamp >= cutoff90 && $0.timestamp < cutoff60 }
        }
    }

    private var headerSubtitle: String? {
        switch filter {
        case .unread: return nil
        case .history30: return "Last 30 Days (Read)"
        case .history60: return "30 – 60 Days Ago"
        case .history90: return "60 – 90 Days Ago"
        }
    }

    private var emptyStateDescription: String {
        switch filter {
        case .unread:
            return ""
        case .history30:
            return "No read alerts in the last 30 days."
        case .history60:
            return "No read alerts between 30 and 60 days ago."
        case .history90:
            return "No read alerts between 60 and 90 days ago."
        }
    }

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
                                if displayedEntries.isEmpty {
                                    VStack(spacing: 6) {
                                        Text("No Alerts")
                                            .font(.title3.bold())
                                            .foregroundStyle(.secondary)

                                        if filter != .unread {
                                            Text(emptyStateDescription)
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary.opacity(0.8))
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.top, 40)
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                } else {
                                    ForEach(Array(displayedEntries.enumerated()), id: \.element.id) { index, entry in
                                        ChangeLogRow(entry: entry) { note in
                                            ChangeLogStore.shared.updateNote(id: entry.id, note: note)
                                            entries = ChangeLogStore.shared.load()
                                        }
                                        .transition(.asymmetric(insertion: .push(from: .bottom), removal: .scale.combined(with: .opacity)))
                                        if index < displayedEntries.count - 1 {
                                            Divider()
                                        }
                                    }
                                }

                                Color.clear.frame(height: 64)
                            }
                            .padding(.horizontal)
                            .padding(.top, 4)
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: filter)
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: displayedEntries.count)
                        }
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
            VStack(alignment: .leading, spacing: 2) {
                Text("Alerts")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color(uiColor: .label))

                if let subtitle = headerSubtitle {
                    Text(subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ThemeManager.shared.current.readableAccent)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            Spacer()
        }
    }
}

private struct ChangeLogRow: View {
    let entry: ChangeLogEntry
    var onNoteChanged: (String) -> Void

    @State private var noteText: String
    @State private var isNoteExpanded: Bool
    @FocusState private var noteFocused: Bool
    @ObservedObject private var theme = ThemeManager.shared

    init(entry: ChangeLogEntry, onNoteChanged: @escaping (String) -> Void) {
        self.entry = entry
        self.onNoteChanged = onNoteChanged
        _noteText = State(initialValue: entry.swapNote ?? "")
        _isNoteExpanded = State(initialValue: entry.kind == .removed || entry.swapNote?.isEmpty == false)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Color status vertical indicator
            Rectangle()
                .fill(kindColor)
                .frame(width: 4)
                .clipShape(.rect(cornerRadius: 2))

            VStack(alignment: .leading, spacing: 6) {
                // Top line: Kind badge + Detection timestamp
                HStack(alignment: .center) {
                    Text(kindLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(kindTextColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(kindColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

                    Spacer()

                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        Text(entry.relativeTimestamp(relativeTo: timeline.date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // Title line: Job + Shift Date
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.shift.job)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color(uiColor: .label))

                    Spacer()

                    Text(entry.shift.startTime.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                // Detail line: Summary description & Shift time range
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.summary)
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: .label).opacity(0.85))

                    Text("\(entry.shift.startTime.formatted(date: .omitted, time: .shortened)) – \(entry.shift.endTime.formatted(date: .omitted, time: .shortened))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                // Swap Note section
                if isNoteExpanded {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("Swapped with? (optional)", text: $noteText)
                            .font(.subheadline)
                            .focused($noteFocused)
                    }
                    .padding(.top, 4)
                    .onChange(of: noteFocused) { wasFocused, isFocused in
                        if wasFocused && !isFocused {
                            onNoteChanged(noteText)
                        }
                    }
                } else if let note = entry.swapNote, !note.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                            .foregroundStyle(theme.current.readableAccent)
                        Text(note)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                } else {
                    Button("Add note") {
                        withAnimation(.easeOut(duration: 0.2)) { isNoteExpanded = true }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
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
