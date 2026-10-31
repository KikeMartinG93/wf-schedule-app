import Foundation

/// What a signed-in session hands `ScheduleSyncCoordinator` to pull shifts
/// with — `UKGScheduleClient`.
@MainActor
protocol ScheduleFetching {
    func fetchShifts() async throws -> [Shift]
}

extension UKGScheduleClient: ScheduleFetching {
    func fetchShifts() async throws -> [Shift] {
        try await fetchSchedule()
    }
}
