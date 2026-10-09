import Foundation

enum ChecklistCategory: String, Codable, CaseIterable, Identifiable {
    case cashOffice = "Cash Office"
    case opener = "Opener"
    case mid = "Mid"
    case closer = "Closer"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .cashOffice: "banknote"
        case .opener: "sunrise"
        case .mid: "sun.max"
        case .closer: "moon.stars"
        }
    }
}

/// A recurring checklist item — "recurring" because these are daily duties
/// (open/mid/close/cash office routines repeat every shift), not one-off
/// to-dos. `dueHour`/`dueMinute` describe a time of day, not a specific date;
/// ChecklistStore resolves that against "today" and resets completion at the
/// start of each new day.
struct ChecklistTask: Codable, Identifiable, Equatable {
    var id: UUID
    var category: ChecklistCategory
    var title: String
    var dueHour: Int
    var dueMinute: Int
    var sortOrder: Int

    init(id: UUID = UUID(), category: ChecklistCategory, title: String, dueHour: Int, dueMinute: Int, sortOrder: Int) {
        self.id = id
        self.category = category
        self.title = title
        self.dueHour = dueHour
        self.dueMinute = dueMinute
        self.sortOrder = sortOrder
    }

    /// Today's due time as a concrete Date, in the device's current calendar/timezone.
    var dueTimeToday: Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = dueHour
        components.minute = dueMinute
        return calendar.date(from: components) ?? Date()
    }

    var dueTimeString: String {
        dueTimeToday.formatted(date: .omitted, time: .shortened)
    }
}

/// Which tasks are checked off, reset automatically at the start of each day.
struct ChecklistState: Codable {
    var lastResetDay: Date
    var completedTaskIDs: Set<UUID>

    static var freshToday: ChecklistState {
        ChecklistState(lastResetDay: Calendar.current.startOfDay(for: Date()), completedTaskIDs: [])
    }
}

/// Which role(s) apply today — a multi-select, since a shift can genuinely be
/// e.g. both Opener and Mid. Resets alongside `ChecklistState` at the start of
/// each new day: your role selection is a daily thing, same as completion.
struct ChecklistDaySelection: Codable {
    var lastResetDay: Date
    var selectedCategories: Set<ChecklistCategory>

    static var freshToday: ChecklistDaySelection {
        ChecklistDaySelection(lastResetDay: Calendar.current.startOfDay(for: Date()), selectedCategories: [])
    }
}
