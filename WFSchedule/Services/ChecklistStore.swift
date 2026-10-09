import Foundation

/// Persists checklist task definitions (per category) and today's completion
/// state. Completion resets automatically the first time this is touched on a
/// new day — there's no explicit "new day" event on iOS, so every read checks
/// `lastResetDay` and clears `completedTaskIDs` if it's stale.
final class ChecklistStore {
    static let shared = ChecklistStore()

    private let tasksURL: URL
    private let stateURL: URL
    private let selectionURL: URL

    private let cacheLock = NSLock()
    private var cachedTasks: [ChecklistTask]?
    private var cachedState: ChecklistState?
    private var cachedSelection: ChecklistDaySelection?

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tasksURL = dir.appendingPathComponent("checklist_tasks.json")
        stateURL = dir.appendingPathComponent("checklist_state.json")
        selectionURL = dir.appendingPathComponent("checklist_selection.json")
    }

    // MARK: - Tasks

    func loadTasks() -> [ChecklistTask] {
        cacheLock.lock()
        if let cached = cachedTasks {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        var tasks: [ChecklistTask] = []
        if let data = try? Data(contentsOf: tasksURL),
           let decoded = try? JSONDecoder().decode([ChecklistTask].self, from: data) {
            tasks = decoded
        }

        if tasks.isEmpty && DemoMode.isEnabled {
            tasks = Self.demoTasks
        }

        cacheLock.lock()
        cachedTasks = tasks
        cacheLock.unlock()
        return tasks
    }

    func tasks(for category: ChecklistCategory) -> [ChecklistTask] {
        loadTasks().filter { $0.category == category }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func addTask(category: ChecklistCategory, title: String, dueHour: Int, dueMinute: Int) {
        var all = loadTasks()
        let nextOrder = (all.filter { $0.category == category }.map(\.sortOrder).max() ?? -1) + 1
        all.append(ChecklistTask(category: category, title: title, dueHour: dueHour, dueMinute: dueMinute, sortOrder: nextOrder))
        saveTasks(all)
    }

    func deleteTask(id: UUID) {
        var all = loadTasks()
        all.removeAll { $0.id == id }
        saveTasks(all)

        var state = loadState()
        state.completedTaskIDs.remove(id)
        saveState(state)

        ChecklistReminderService.cancelReminder(taskID: id)
    }

    private func saveTasks(_ tasks: [ChecklistTask]) {
        cacheLock.lock()
        cachedTasks = tasks
        cacheLock.unlock()
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        try? data.write(to: tasksURL, options: .atomic)
    }

    // MARK: - Completion state

    func loadState() -> ChecklistState {
        cacheLock.lock()
        if let state = cachedState {
            if Calendar.current.isDateInToday(state.lastResetDay) {
                cacheLock.unlock()
                return state
            }
        }
        cacheLock.unlock()

        var state: ChecklistState
        if let data = try? Data(contentsOf: stateURL),
           let decoded = try? JSONDecoder().decode(ChecklistState.self, from: data) {
            state = decoded
        } else {
            state = .freshToday
        }

        if !Calendar.current.isDateInToday(state.lastResetDay) {
            state = .freshToday
            saveState(state)
        } else {
            cacheLock.lock()
            cachedState = state
            cacheLock.unlock()
        }
        return state
    }

    func isCompleted(_ taskID: UUID) -> Bool {
        loadState().completedTaskIDs.contains(taskID)
    }

    func setCompleted(_ taskID: UUID, completed: Bool) {
        var state = loadState()
        if completed {
            state.completedTaskIDs.insert(taskID)
        } else {
            state.completedTaskIDs.remove(taskID)
        }
        saveState(state)
    }

    private func saveState(_ state: ChecklistState) {
        cacheLock.lock()
        cachedState = state
        cacheLock.unlock()
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    // MARK: - Today's role selection

    func loadSelection() -> ChecklistDaySelection {
        cacheLock.lock()
        if let selection = cachedSelection {
            if Calendar.current.isDateInToday(selection.lastResetDay) {
                cacheLock.unlock()
                return selection
            }
        }
        cacheLock.unlock()

        var selection: ChecklistDaySelection
        if let data = try? Data(contentsOf: selectionURL),
           let decoded = try? JSONDecoder().decode(ChecklistDaySelection.self, from: data) {
            selection = decoded
        } else {
            selection = .freshToday
        }

        if !Calendar.current.isDateInToday(selection.lastResetDay) {
            selection = .freshToday
            saveSelection(selection)
        } else {
            cacheLock.lock()
            cachedSelection = selection
            cacheLock.unlock()
        }

        if selection.selectedCategories.isEmpty && DemoMode.isEnabled {
            selection.selectedCategories = [.cashOffice, .opener]
        }

        return selection
    }

    func setSelectedCategories(_ categories: Set<ChecklistCategory>) {
        var selection = loadSelection()
        selection.selectedCategories = categories
        saveSelection(selection)
    }

    private func saveSelection(_ selection: ChecklistDaySelection) {
        cacheLock.lock()
        cachedSelection = selection
        cacheLock.unlock()
        guard let data = try? JSONEncoder().encode(selection) else { return }
        try? data.write(to: selectionURL, options: .atomic)
    }

    // MARK: - Demo Sample Tasks

    private static var demoTasks: [ChecklistTask] {
        [
            ChecklistTask(category: .cashOffice, title: "Count safe & verify opening change", dueHour: 8, dueMinute: 0, sortOrder: 0),
            ChecklistTask(category: .cashOffice, title: "Audit cashier tills & pickups", dueHour: 13, dueMinute: 0, sortOrder: 1),
            ChecklistTask(category: .cashOffice, title: "Prepare daily bank deposit bag", dueHour: 17, dueMinute: 0, sortOrder: 2),
            ChecklistTask(category: .opener, title: "Turn on registers & receipt printers", dueHour: 7, dueMinute: 0, sortOrder: 0),
            ChecklistTask(category: .opener, title: "Inspect refrigeration temperature logs", dueHour: 7, dueMinute: 30, sortOrder: 1),
            ChecklistTask(category: .mid, title: "Mid-day break & meal coverage rotation", dueHour: 12, dueMinute: 30, sortOrder: 0),
            ChecklistTask(category: .mid, title: "Restock register paper & customer supplies", dueHour: 14, dueMinute: 30, sortOrder: 1),
            ChecklistTask(category: .closer, title: "Collect all tills and lock safe", dueHour: 21, dueMinute: 0, sortOrder: 0),
            ChecklistTask(category: .closer, title: "Perform final store security & exit check", dueHour: 21, dueMinute: 30, sortOrder: 1),
        ]
    }
}
