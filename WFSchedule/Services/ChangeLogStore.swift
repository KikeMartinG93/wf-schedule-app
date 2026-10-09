import Foundation

/// Persists the schedule change history shown in AlertsView. Capped at
/// `maxEntries` so this can't grow unbounded across months of daily syncs.
final class ChangeLogStore {
    static let shared = ChangeLogStore()

    private let fileURL: URL
    private let maxEntries = 200

    private let cacheLock = NSLock()
    private var cachedEntries: [ChangeLogEntry]?

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("change_log.json")
    }

    func load() -> [ChangeLogEntry] {
        if DemoMode.isEnabled { return DemoMode.entries }
        cacheLock.lock()
        if let cached = cachedEntries {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        var entries: [ChangeLogEntry] = []
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([ChangeLogEntry].self, from: data) {
            entries = decoded
        }

        cacheLock.lock()
        cachedEntries = entries
        cacheLock.unlock()
        return entries
    }

    func append(_ newEntries: [ChangeLogEntry]) {
        guard !newEntries.isEmpty, !DemoMode.isEnabled else { return }
        var all = load()
        all.append(contentsOf: newEntries)
        all.sort { $0.timestamp > $1.timestamp }
        if all.count > maxEntries {
            all = Array(all.prefix(maxEntries))
        }
        save(all)
    }

    /// Records the user's own answer to "who was this swapped with" — the one
    /// piece AlertsView asks for on a text field since UKG's data doesn't have it.
    func updateNote(id: UUID, note: String) {
        var all = load()
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        all[index].swapNote = note.isEmpty ? nil : note
        save(all)
    }

    func markAllSeen() {
        var all = load()
        guard all.contains(where: { !$0.seen }) else { return }
        for index in all.indices { all[index].seen = true }
        save(all)
    }

    private func save(_ entries: [ChangeLogEntry]) {
        if DemoMode.isEnabled {
            DemoMode.entries = entries
            return
        }
        cacheLock.lock()
        cachedEntries = entries
        cacheLock.unlock()
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
