import Foundation
import WidgetKit

/// Persists the last known schedule snapshot on-device (Application Support directory)
/// so change detection survives app relaunches and background task runs.
final class ScheduleStore {
    static let shared = ScheduleStore()

    /// Posted after every save so views that already loaded the schedule (Home)
    /// can re-read it when a sync finishes elsewhere.
    static let didChangeNotification = Notification.Name("ScheduleStoreDidChange")

    private let fileURL: URL

    /// Decoded copy of the on-disk snapshot. Home, List and Alerts each call
    /// `load()` when they're created and again on every change notification, and
    /// SwiftUI creates views often — without this, each of those was a disk read
    /// plus a full JSON decode on the main thread.
    private let cacheLock = NSLock()
    private var cachedSnapshot: ScheduleSnapshot?
    private var cacheIsValid = false

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("schedule_snapshot.json")
    }

    func load() -> ScheduleSnapshot? {
        if DemoMode.isEnabled { return DemoMode.snapshot() }
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if cacheIsValid { return cachedSnapshot }
        var snapshot: ScheduleSnapshot?
        if let data = try? Data(contentsOf: fileURL) {
            snapshot = try? JSONDecoder().decode(ScheduleSnapshot.self, from: data)
        }
        cachedSnapshot = snapshot
        cacheIsValid = true
        return snapshot
    }

    func save(_ snapshot: ScheduleSnapshot) {
        if DemoMode.isEnabled { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        do {
            try data.write(to: fileURL, options: .atomic)
            cacheLock.lock()
            cachedSnapshot = snapshot
            cacheIsValid = true
            cacheLock.unlock()
        } catch {
            // Disk write failed: don't serve a snapshot that isn't on disk.
            cacheLock.lock()
            cacheIsValid = false
            cacheLock.unlock()
        }
        publishToSharedContainer(data)
        ShiftIndexer.reindex()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    /// Copy for the Next Shift widget, which runs in its own process and can't
    /// see this app's Application Support directory.
    private func publishToSharedContainer(_ data: Data) {
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.marting.WFM")?
            .appendingPathComponent("schedule_snapshot.json") else { return }
        try? data.write(to: url, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Existing installs already have a snapshot on disk from before the widget
    /// existed; this pushes it into the shared container without waiting for the
    /// next sync.
    func republishExistingSnapshot() {
        if DemoMode.isEnabled {
            if let data = try? JSONEncoder().encode(DemoMode.snapshot()) { publishToSharedContainer(data) }
        } else if let data = try? Data(contentsOf: fileURL) {
            publishToSharedContainer(data)
        }
    }
}
