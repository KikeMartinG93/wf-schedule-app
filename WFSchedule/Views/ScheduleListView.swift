import SwiftUI

struct ScheduleListView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @State private var shifts: [Shift] = ScheduleStore.shared.load()?.shifts ?? []
    @State private var lastSynced: Date? = ScheduleStore.shared.load()?.fetchedAt
    @State private var isSyncing = false
    @State private var syncError: String?

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 20) {
                                if let syncError {
                                    Text(syncError)
                                        .font(.footnote)
                                        .foregroundStyle(.white)
                                        .padding(12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .glassEffect(.regular.tint(ThemeManager.shared.highContrast ? Color.buttonFill(.gray) : Color.buttonFill(.red)), in: .rect(cornerRadius: 16))
                                }

                                if let lastSynced {
                                    Text("Last synced \(lastSynced.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)
                                }

                                VStack(alignment: .leading, spacing: 26) {
                                    ForEach(groupedByDay, id: \.day) { group in
                                        DaySection(day: group.day, shifts: group.shifts)
                                            .id(group.day)
                                    }
                                }

                                if shifts.isEmpty && !isSyncing {
                                    ContentUnavailableView(
                                        "No shifts yet",
                                        systemImage: "calendar.badge.clock",
                                        description: Text("Pull to sync your UKG schedule.")
                                    )
                                    .padding(.top, 60)
                                }

                                // Breathing room so the bottom blur fade doesn't sit
                                // on top of the last row's text.
                                Color.clear.frame(height: 40)
                            }
                            .padding(.horizontal)
                        }
                        .refreshable { await sync(force: true) }
                        // Opens on today, not the top of the whole list — older
                        // shifts are still above it, reachable by scrolling up.
                        // Fires on first appear (using whatever's cached on disk)
                        // and again whenever a sync brings in a different set of
                        // days, since `groupedByDay`'s anchor day can shift.
                        .onAppear { scrollToToday(proxy: proxy) }
                        .onChange(of: shifts) { scrollToToday(proxy: proxy) }
                        // Same as Settings and Breaks: the title is a top bar the
                        // list scrolls under, fading out softly instead of being
                        // cut off along a hard line.
                        .safeAreaBar(edge: .top) {
                            header
                                .padding(.horizontal)
                                .padding(.top, 8)
                                .padding(.bottom, 6)
                        }
                        .scrollEdgeEffectStyle(.soft, for: .top)
                        .scrollEdgeEffectStyle(.soft, for: .bottom)
                    }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onReceive(NotificationCenter.default.publisher(for: ScheduleStore.didChangeNotification)) { _ in
                let snapshot = ScheduleStore.shared.load()
                shifts = snapshot?.shifts ?? []
                lastSynced = snapshot?.fetchedAt
            }
            .task {
                guard sessionManager.state == .authenticated else { return }
                await sync()
            }
        }
    }

    /// Same layout as Home's monthHeader: bold large title on the leading
    /// edge, the row's action (refresh here, month-navigation arrows there)
    /// trailing, baseline-aligned.
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("My Schedule")
                .font(.largeTitle.bold())
                .foregroundStyle(Color(uiColor: .label))

            Spacer()

            Button {
                Task { await sync(force: true) }
            } label: {
                if isSyncing {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3)
                }
            }
            .buttonStyle(.glass)
            .disabled(isSyncing)
        }
    }

    private var groupedByDay: [(day: Date, shifts: [Shift])] {
        let sorted = shifts.sorted { $0.startTime < $1.startTime }
        let groups = Dictionary(grouping: sorted) { calendar.startOfDay(for: $0.startTime) }
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }

    /// Docks today's day section at the top of the visible area. Falls back to
    /// the nearest upcoming day if today has no shift, or the most recent past
    /// day if every shift is already in the past.
    ///
    /// Deferred a tick: called from `.onAppear` on cold launch, before
    /// `LazyVStack` has laid out the day sections it needs to scroll to —
    /// `ScrollViewProxy.scrollTo` needs the target `.id` to already exist in
    /// the rendered hierarchy, so calling it synchronously there can silently
    /// no-op. Dispatching to the next run loop turn runs it after that first
    /// layout pass.
    private func scrollToToday(proxy: ScrollViewProxy) {
        let today = calendar.startOfDay(for: Date())
        let days = groupedByDay.map(\.day)
        guard !days.isEmpty else { return }
        let target = days.first(where: { $0 >= today }) ?? days.last!
        DispatchQueue.main.async {
            proxy.scrollTo(target, anchor: .top)
        }
    }

    private func sync(force: Bool = false) async {
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }
        do {
            try await ScheduleSyncCoordinator.runSync(force: force)
            if let snapshot = ScheduleStore.shared.load() {
                shifts = snapshot.shifts
                lastSynced = snapshot.fetchedAt
            }
        } catch {
            syncError = error.localizedDescription
        }
    }
}

private struct DaySection: View {
    let day: Date
    let shifts: [Shift]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.title3.bold())

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(shifts.enumerated()), id: \.element.id) { index, shift in
                    ShiftRow(shift: shift)
                    if index < shifts.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }
}

private struct ShiftRow: View {
    let shift: Shift

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle()
                .fill(shift.accentColor(theme: theme.current))
                .frame(width: 4)
                .clipShape(.rect(cornerRadius: 2))

            VStack(alignment: .leading, spacing: 4) {
                Text(shift.job)
                    .font(.headline)
                if let location = shift.location {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(shift.startTime.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.weight(.semibold))
                Text(shift.endTime.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
    }
}
