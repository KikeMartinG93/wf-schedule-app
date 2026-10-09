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

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tasksURL = dir.appendingPathComponent("checklist_tasks.json")
        stateURL = dir.appendingPathComponent("checklist_state.json")
        selectionURL = dir.appendingPathComponent("checklist_selection.json")
    }

    // MARK: - Tasks

    func loadTasks() -> [ChecklistTask] {
        guard let data = try? Data(contentsOf: tasksURL) else { return [] }
        return (try? JSONDecoder().decode([ChecklistTask].self, from: data)) ?? []
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
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        try? data.write(to: tasksURL, options: .atomic)
    }

    // MARK: - Completion state

    func loadState() -> ChecklistState {
        guard let data = try? Data(contentsOf: stateURL),
              var state = try? JSONDecoder().decode(ChecklistState.self, from: data) else {
            return .freshToday
        }
        if !Calendar.current.isDateInToday(state.lastResetDay) {
            state = .freshToday
            saveState(state)
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
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    // MARK: - Today's role selection

    func loadSelection() -> ChecklistDaySelection {
        guard let data = try? Data(contentsOf: selectionURL),
              var selection = try? JSONDecoder().decode(ChecklistDaySelection.self, from: data) else {
            return .freshToday
        }
        if !Calendar.current.isDateInToday(selection.lastResetDay) {
            selection = .freshToday
            saveSelection(selection)
        }
        return selection
    }

    func setSelectedCategories(_ categories: Set<ChecklistCategory>) {
        var selection = loadSelection()
        selection.selectedCategories = categories
        saveSelection(selection)
    }

    private func saveSelection(_ selection: ChecklistDaySelection) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        try? data.write(to: selectionURL, options: .atomic)
    }
}
