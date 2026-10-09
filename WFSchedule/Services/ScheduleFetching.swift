import Foundation

/// What a signed-in session hands `ScheduleSyncCoordinator` to pull shifts
/// with — `UKGScheduleClient` for the UKG Pro backup sign-in, and
/// `InnerviewScheduleClient` for Innerview Login.
@MainActor
protocol ScheduleFetching {
    func fetchShifts() async throws -> [Shift]
}

extension UKGScheduleClient: ScheduleFetching {
    func fetchShifts() async throws -> [Shift] {
        try await fetchSchedule()
    }
}
