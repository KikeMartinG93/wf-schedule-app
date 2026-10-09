import Foundation

/// Mirrors the real response shape of `POST /myschedule/events` (UKG Workforce
/// Dimensions ESS), captured via a HAR export from a real authenticated device
/// session on 2026-09-01. Only the fields this app actually uses are modeled —
/// the live response has many more (labor category breakdowns, cost centers,
/// etc.) that we don't need.
///
/// It's a POST, not a GET — no query params at all; the date range and options
/// go in a JSON body (see `WFScheduleEventsRequest`). Earlier guesses at a GET
/// with query params were wrong, which is the real reason those attempts never
/// worked, not any of the webview/visibility theories chased before this.
struct WFScheduleEventsResponse: Decodable {
    var regularShifts: [WFRawShift]
    var transferShifts: [WFRawShift]
    var openShifts: [WFRawShift]
}

/// Request body for `POST /myschedule/events`, matching a real captured request
/// byte-for-byte except `dateSpan`. `calendarConfigId` is specific to this
/// tenant/user's calendar configuration — captured as 3004002; if requests ever
/// start failing for a different account, this is the first thing to re-check
/// (there's no known way to derive it other than capturing a real request).
struct WFScheduleEventsRequest: Encodable {
    struct Body: Encodable {
        struct DateSpan: Encodable {
            var start: String
            var end: String
        }
        var calendarConfigId: Int = 3004002
        var includedEntities: [String] = [
            "entity.transfershift", "entity.regularshift", "entity.paycodeedit",
            "entity.openshift", "entity.holiday", "entity.swaprequest",
            "entity.openshiftrequest", "entity.timeoffrequest", "entity.coverrequest",
            "entity.availabilityrequests", "entity.availabilitypatternrequests"
        ]
        var includedCoverRequestsStatuses: [String] = []
        var includedSwapRequestsStatuses: [String] = []
        var includedTimeOffRequestsStatuses: [String] = []
        var includedOpenShiftRequestsStatuses: [String] = []
        var includedSelfScheduleRequestsStatuses: [String] = []
        var includedAvailabilityRequestsStatuses: [String] = []
        var includedAvailabilityPatternRequestsStatuses: [String] = []
        var dateSpan: DateSpan
        var showJobColoring: Bool = true
        var showOrgPathToDisplay: Bool = true
        var includeEmployeePreferences: Bool = true
        var includeNodeAddress: Bool = true
        var removeDuplicatedEntities: Bool = true
        var hideInvisibleTORPayCodes: Bool = true
    }
    var data: Body
}

struct WFRawShift: Decodable {
    var id: Int
    /// Whole-shift start/end, e.g. "2026-08-31T13:30:00" — no timezone offset;
    /// this is wall-clock time in the store's local zone.
    var startDateTime: String
    var endDateTime: String
    var posted: Bool
    var deleted: Bool
    var segments: [WFRawSegment]
}

struct WFRawSegment: Decodable {
    var startDateTime: String
    var endDateTime: String
    /// "REGULAR_SEGMENT" | "BREAK_SEGMENT" | "TRANSFER_SEGMENT"
    var type: String
    var orgJobRef: WFRawOrgJobRef?
    /// Present on TRANSFER_SEGMENT: e.g.
    /// "WFM/WFM Retail/CA-01/CA East Bay/GIL-10530/Customer Service Team/Front End/Cash Office;;;;"
    var transferString: String?
}

struct WFRawOrgJobRef: Decodable {
    /// Full slash-delimited org path, e.g.
    /// "WFM/WFM Retail/CA-01/CA East Bay/GIL-10530/Customer Service Team/Front End/Supervisor"
    var qualifier: String
}

enum WFScheduleMapper {
    private static let wallClockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    /// A component of an org path that looks like a store code (letters + dash + digits,
    /// e.g. "GIL-10530"). Used to surface a short, human location instead of the full path.
    private static let storeCodePattern = try? NSRegularExpression(pattern: "^[A-Z]{2,5}-\\d{3,6}$")

    static func shifts(from response: WFScheduleEventsResponse) -> [Shift] {
        let regular = response.regularShifts.compactMap { shift(from: $0, kind: .regular) }
        let transfers = response.transferShifts.compactMap { shift(from: $0, kind: .transfer) }
        return regular + transfers
    }

    private static func shift(from raw: WFRawShift, kind: ShiftKind) -> Shift? {
        guard raw.posted, !raw.deleted,
              let start = wallClockFormatter.date(from: raw.startDateTime),
              let end = wallClockFormatter.date(from: raw.endDateTime) else {
            return nil
        }

        // For a transfer shift, describe the job using the TRANSFER_SEGMENT (what's
        // different about this shift); otherwise use the first REGULAR_SEGMENT.
        let describingSegment = raw.segments.first { $0.type == "TRANSFER_SEGMENT" }
            ?? raw.segments.first { $0.type == "REGULAR_SEGMENT" }

        let path = describingSegment?.transferString.map(stripTrailingSemicolons)
            ?? describingSegment?.orgJobRef?.qualifier

        let (job, location) = jobAndLocation(fromPath: path)

        return Shift(
            ukgRecordId: String(raw.id),
            date: Calendar.current.startOfDay(for: start),
            startTime: start,
            endTime: end,
            job: job,
            location: location,
            kind: kind,
            payCode: nil,
            notes: nil
        )
    }

    private static func stripTrailingSemicolons(_ s: String) -> String {
        var s = s
        while s.hasSuffix(";") { s.removeLast() }
        return s
    }

    private static func jobAndLocation(fromPath path: String?) -> (job: String, location: String?) {
        guard let path else { return ("Shift", nil) }
        let components = path.split(separator: "/").map(String.init)
        let job = components.last ?? "Shift"
        let location = components.first { component in
            guard let storeCodePattern else { return false }
            let range = NSRange(component.startIndex..., in: component)
            return storeCodePattern.firstMatch(in: component, range: range) != nil
        }
        return (job, location)
    }
}
