import SwiftUI

/// A single daily checklist covering whichever role(s) apply today. Role
/// selection is a multi-select (any number of Cash Office/Opener/Mid/Closer,
/// not fixed at any particular count) — a shift can genuinely span more than
/// one role — and both the selection and task completion reset automatically
/// each new day (see ChecklistStore).
struct ChecklistView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategories: Set<ChecklistCategory> = []
    @State private var tasksByCategory: [ChecklistCategory: [ChecklistTask]] = [:]
    @State private var completedIDs: Set<UUID> = []
    @State private var addingTaskFor: ChecklistCategory?

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()

                VStack(spacing: 0) {
                    header
                        .padding(.horizontal)
                        .padding(.top, 8)

                    roleSelector
                        .padding(.horizontal)
                        .padding(.top, 14)

                    if selectedCategories.isEmpty {
                        Spacer()
                        ContentUnavailableView(
                            "Pick your role(s) for today",
                            systemImage: "checklist",
                            description: Text("Select above — a shift can cover more than one role.")
                        )
                        Spacer()
                    } else {
                        checklist
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            reloadAll()
            ChecklistReminderService.refreshAllReminders()
        }
        .sheet(item: $addingTaskFor) { category in
            AddChecklistTaskView(category: category) { reloadAll() }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Checklist")
                .font(.largeTitle.bold())
            Spacer()
            Button("Done") { dismiss() }
                .font(.headline)
                .buttonStyle(.plain)
                .foregroundStyle(ThemeManager.shared.current.readableAccent)
        }
    }

    private var roleSelector: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(ChecklistCategory.allCases) { category in
                RoleChip(category: category, isSelected: selectedCategories.contains(category)) {
                    toggleCategory(category)
                }
            }
        }
    }

    private var checklist: some View {
        List {
            ForEach(ChecklistCategory.allCases.filter { selectedCategories.contains($0) }) { category in
                Section {
                    let tasks = tasksByCategory[category] ?? []
                    if tasks.isEmpty {
                        Text("No tasks yet")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(tasks) { task in
                            TaskRow(
                                task: task,
                                isCompleted: completedIDs.contains(task.id),
                                onToggle: { toggle(task) }
                            )
                        }
                        .onDelete { offsets in delete(offsets, in: category) }
                    }

                    Button {
                        addingTaskFor = category
                    } label: {
                        Label("Add task", systemImage: "plus.circle")
                    }
                } header: {
                    Label(category.rawValue, systemImage: category.systemImage)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func toggleCategory(_ category: ChecklistCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
        ChecklistStore.shared.setSelectedCategories(selectedCategories)
    }

    private func reloadAll() {
        selectedCategories = ChecklistStore.shared.loadSelection().selectedCategories
        var dict: [ChecklistCategory: [ChecklistTask]] = [:]
        for category in ChecklistCategory.allCases {
            dict[category] = ChecklistStore.shared.tasks(for: category)
        }
        tasksByCategory = dict
        completedIDs = ChecklistStore.shared.loadState().completedTaskIDs
    }

    private func toggle(_ task: ChecklistTask) {
        let newValue = !completedIDs.contains(task.id)
        ChecklistStore.shared.setCompleted(task.id, completed: newValue)
        ChecklistReminderService.handleToggled(taskID: task.id, isCompleted: newValue)
        completedIDs = ChecklistStore.shared.loadState().completedTaskIDs
    }

    private func delete(_ offsets: IndexSet, in category: ChecklistCategory) {
        let tasks = tasksByCategory[category] ?? []
        for index in offsets {
            ChecklistStore.shared.deleteTask(id: tasks[index].id)
        }
        reloadAll()
    }
}

private struct RoleChip: View {
    let category: ChecklistCategory
    let isSelected: Bool
    var onTap: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: category.systemImage)
                Text(category.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(
                isSelected ? theme.current.accent : Color(.secondarySystemBackground).opacity(0.6),
                in: .rect(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TaskRow: View {
    let task: ChecklistTask
    let isCompleted: Bool
    var onToggle: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isCompleted ? theme.current.accent : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .strikethrough(isCompleted)
                        .foregroundStyle(isCompleted ? .secondary : .primary)
                    Text("Due \(task.dueTimeString)")
                        .font(.caption)
                        // High contrast has no red: overdue is bold primary text instead.
                        .foregroundStyle(isOverdue ? (theme.highContrast ? AnyShapeStyle(.primary) : AnyShapeStyle(.red)) : AnyShapeStyle(.secondary))
                        .fontWeight(isOverdue && theme.highContrast ? .bold : nil)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var isOverdue: Bool {
        !isCompleted && Date() >= task.dueTimeToday
    }
}

private struct AddChecklistTaskView: View {
    let category: ChecklistCategory
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var dueTime = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("What needs to get done?", text: $title)
                }
                Section {
                    DatePicker("Time", selection: $dueTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                } header: {
                    Text("Due by")
                } footer: {
                    Text("If it's not checked off by this time, you'll get a reminder every 10 minutes until it is.")
                }
            }
            .navigationTitle("New \(category.rawValue) Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: dueTime)
                        ChecklistStore.shared.addTask(
                            category: category,
                            title: title.trimmingCharacters(in: .whitespaces),
                            dueHour: comps.hour ?? 9,
                            dueMinute: comps.minute ?? 0
                        )
                        onSaved()
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
