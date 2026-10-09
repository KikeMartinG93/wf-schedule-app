import AppIntents
import CoreSpotlight
import Foundation

/// A shift as Siri, Shortcuts and Spotlight see it. Indexed (see
/// `ShiftIndexer`) so the system can find and reason about your shifts.
struct ShiftEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Shift"
    static let defaultQuery = ShiftQuery()

    let id: String

    @Property(title: "Job")
    var job: String

    @Property(title: "Start")
    var start: Date

    @Property(title: "End")
    var end: Date

    @Property(title: "Location")
    var location: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(job)",
            subtitle: "\(start.formatted(date: .abbreviated, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
        )
    }

    init(_ shift: Shift) {
        id = shift.id
        job = shift.job
        start = shift.startTime
        end = shift.endTime
        location = shift.location
    }
}

enum ShiftLibrary {
    static func allShifts() -> [Shift] {
        (ScheduleStore.shared.load()?.shifts ?? []).filter { $0.kind != .timeOff }
    }

    static func nextShift(after date: Date = Date()) -> Shift? {
        allShifts().filter { $0.startTime > date }.min { $0.startTime < $1.startTime }
    }

    static func shifts(on day: Date) -> [Shift] {
        allShifts()
            .filter { Calendar.current.isDate($0.startTime, inSameDayAs: day) }
            .sorted { $0.startTime < $1.startTime }
    }
}

struct ShiftQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ShiftEntity] {
        ShiftLibrary.allShifts().filter { identifiers.contains($0.id) }.map(ShiftEntity.init)
    }

    func entities(matching string: String) async throws -> [ShiftEntity] {
        ShiftLibrary.allShifts()
            .filter { $0.job.localizedCaseInsensitiveContains(string) }
            .sorted { $0.startTime < $1.startTime }
            .map(ShiftEntity.init)
    }

    func suggestedEntities() async throws -> [ShiftEntity] {
        let now = Date()
        return ShiftLibrary.allShifts()
            .filter { $0.endTime > now }
            .sorted { $0.startTime < $1.startTime }
            .prefix(10)
            .map(ShiftEntity.init)
    }
}

/// Keeps the system's index of your shifts in step with the saved schedule.
enum ShiftIndexer {
    static func reindex() {
        let entities = ShiftLibrary.allShifts().map(ShiftEntity.init)
        Task {
            let index = CSSearchableIndex.default()
            try? await index.deleteAppEntities(ofType: ShiftEntity.self)
            try? await index.indexAppEntities(entities)
        }
    }
}
