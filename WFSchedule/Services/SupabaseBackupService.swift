import Foundation
import Observation

/// Optional Supabase email/password backup of the local shift history.
/// UKG login stays separate; this only syncs what is already on disk.
/// Uses Auth + PostgREST over URLSession (same endpoints as supabase-swift)
/// so the sideloaded Xcode project does not need an SPM package to build.
@MainActor
@Observable
final class SupabaseBackupService {
    static let shared = SupabaseBackupService()

    private static let accessTokenKey = "supabaseAccessToken"
    private static let refreshTokenKey = "supabaseRefreshToken"
    private static let userIDKey = "supabaseUserID"
    private static let emailKey = "supabaseEmail"
    private static let lastBackupKey = "supabaseLastBackupAt"

    private(set) var email: String?
    private(set) var userID: String?
    private(set) var lastBackupAt: Date?
    private(set) var isBusy = false
    private(set) var statusMessage: String?

    var isSignedIn: Bool { userID != nil && accessToken != nil }

    private var accessToken: String?
    private var refreshToken: String?

    private let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private init() {
        restoreSessionFromDefaults()
    }

    // MARK: - Auth

    func signUp(email: String, password: String) async throws {
        try ensureConfigured()
        isBusy = true
        statusMessage = nil
        defer { isBusy = false }

        let body: [String: Any] = [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "password": password
        ]
        let data = try await postJSON(
            path: "/auth/v1/signup",
            body: body,
            authorized: false
        )
        try applyAuthResponse(data, fallbackEmail: email)
        statusMessage = String(localized: "Account created. Backing up…")
        try await backupNow()
    }

    func signIn(email: String, password: String) async throws {
        try ensureConfigured()
        isBusy = true
        statusMessage = nil
        defer { isBusy = false }

        let body: [String: Any] = [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "password": password
        ]
        let data = try await postJSON(
            path: "/auth/v1/token?grant_type=password",
            body: body,
            authorized: false
        )
        try applyAuthResponse(data, fallbackEmail: email)
        statusMessage = String(localized: "Signed in. Restoring…")
        try await restoreAndMerge()
        try await backupNow()
    }

    func signOut() {
        accessToken = nil
        refreshToken = nil
        userID = nil
        email = nil
        UserDefaults.standard.removeObject(forKey: Self.accessTokenKey)
        UserDefaults.standard.removeObject(forKey: Self.refreshTokenKey)
        UserDefaults.standard.removeObject(forKey: Self.userIDKey)
        UserDefaults.standard.removeObject(forKey: Self.emailKey)
        statusMessage = String(localized: "Signed out of cloud backup.")
    }

    /// Rehydrate tokens after launch; refresh if needed.
    func restoreSessionIfNeeded() async {
        guard SupabaseConfig.isConfigured, accessToken != nil else { return }
        do {
            try await refreshAccessTokenIfPossible()
            _ = try await getJSON(path: "/auth/v1/user", authorized: true)
        } catch {
            // Stale session — clear quietly; user can sign in again.
            signOut()
            statusMessage = nil
        }
    }

    // MARK: - Backup / restore

    func backupNow() async throws {
        try ensureConfigured()
        guard let userID, accessToken != nil else {
            throw SupabaseBackupError.notSignedIn
        }
        isBusy = true
        statusMessage = nil
        defer { isBusy = false }

        let shifts = ScheduleStore.shared.load()?.shifts ?? []
        guard !shifts.isEmpty else {
            lastBackupAt = Date()
            UserDefaults.standard.set(lastBackupAt, forKey: Self.lastBackupKey)
            statusMessage = String(localized: "Nothing to back up yet.")
            return
        }

        let rows = shifts.map { RemoteShiftRow(from: $0, userID: userID) }
        try await upsertShifts(rows)
        lastBackupAt = Date()
        UserDefaults.standard.set(lastBackupAt, forKey: Self.lastBackupKey)
        statusMessage = String(localized: "Backup complete.")
    }

    /// Pull cloud rows and merge into the local snapshot (cloud fills history;
    /// local / newer `updated_at` wins on id conflicts).
    func restoreAndMerge() async throws {
        try ensureConfigured()
        guard userID != nil, accessToken != nil else {
            throw SupabaseBackupError.notSignedIn
        }
        isBusy = true
        statusMessage = nil
        defer { isBusy = false }

        let remote = try await fetchAllShifts()
        let remoteShifts = remote.map(\.asShift)
        let previous = ScheduleStore.shared.load()
        let localShifts = previous?.shifts ?? []

        var byID = Dictionary(localShifts.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        for shift in remoteShifts {
            if byID[shift.id] == nil {
                byID[shift.id] = shift
            }
        }

        let merged = ScheduleSnapshot(
            fetchedAt: previous?.fetchedAt ?? Date(),
            shifts: byID.values.sorted { $0.startTime < $1.startTime },
            pendingRemovalMisses: previous?.pendingRemovalMisses ?? [:]
        )
        ScheduleStore.shared.save(merged, triggerCloudBackup: false)
        statusMessage = String(localized: "Restored \(remoteShifts.count) shift(s) from the cloud.")
    }

    /// Fire-and-forget upsert after a successful local schedule save.
    func backupAfterLocalSaveIfSignedIn() {
        guard SupabaseConfig.isConfigured, isSignedIn, !DemoMode.isEnabled else { return }
        Task { @MainActor in
            do {
                try await backupNow()
            } catch {
                // Never fail a UKG sync because backup failed.
                statusMessage = String(localized: "Cloud backup failed. Try again in Settings.")
            }
        }
    }

    // MARK: - Networking

    private func ensureConfigured() throws {
        guard SupabaseConfig.isConfigured, SupabaseConfig.projectURL != nil else {
            throw SupabaseBackupError.notConfigured
        }
    }

    private func restoreSessionFromDefaults() {
        let defaults = UserDefaults.standard
        accessToken = defaults.string(forKey: Self.accessTokenKey)
        refreshToken = defaults.string(forKey: Self.refreshTokenKey)
        userID = defaults.string(forKey: Self.userIDKey)
        email = defaults.string(forKey: Self.emailKey)
        lastBackupAt = defaults.object(forKey: Self.lastBackupKey) as? Date
    }

    private func persistSession() {
        let defaults = UserDefaults.standard
        defaults.set(accessToken, forKey: Self.accessTokenKey)
        defaults.set(refreshToken, forKey: Self.refreshTokenKey)
        defaults.set(userID, forKey: Self.userIDKey)
        defaults.set(email, forKey: Self.emailKey)
    }

    private func applyAuthResponse(_ data: Data, fallbackEmail: String) throws {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        // signup may return user nested without tokens when email confirm is on
        if let access = json?["access_token"] as? String {
            accessToken = access
            refreshToken = json?["refresh_token"] as? String
            if let user = json?["user"] as? [String: Any] {
                userID = user["id"] as? String
                email = (user["email"] as? String) ?? fallbackEmail
            } else {
                email = fallbackEmail
            }
            persistSession()
            return
        }
        if let user = json?["user"] as? [String: Any], let id = user["id"] as? String {
            // Confirm-email mode: account exists but no session yet.
            userID = id
            email = (user["email"] as? String) ?? fallbackEmail
            accessToken = nil
            refreshToken = nil
            persistSession()
            throw SupabaseBackupError.emailConfirmationRequired
        }
        if let msg = json?["msg"] as? String ?? json?["error_description"] as? String ?? json?["message"] as? String {
            throw SupabaseBackupError.server(msg)
        }
        throw SupabaseBackupError.server(String(localized: "Unexpected auth response."))
    }

    private func refreshAccessTokenIfPossible() async throws {
        guard let refreshToken, let url = SupabaseConfig.projectURL else { return }
        var request = URLRequest(url: url.appending(path: "/auth/v1/token").appending(queryItems: [
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ]))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SupabaseBackupError.sessionExpired
        }
        try applyAuthResponse(data, fallbackEmail: email ?? "")
    }

    private func upsertShifts(_ rows: [RemoteShiftRow]) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(rows)
        func send() async throws -> (Data, URLResponse) {
            var request = try authorizedRequest(
                path: "/rest/v1/shifts?on_conflict=user_id,id",
                method: "POST"
            )
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
            request.httpBody = body
            return try await URLSession.shared.data(for: request)
        }
        var (data, response) = try await send()
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            try await refreshAccessTokenIfPossible()
            (data, response) = try await send()
        }
        _ = data
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SupabaseBackupError.server(String(localized: "Could not upload shifts."))
        }
    }

    private func fetchAllShifts() async throws -> [RemoteShiftRow] {
        let data: Data
        do {
            data = try await getJSON(
                path: "/rest/v1/shifts?select=*&order=start_time.asc",
                authorized: true
            )
        } catch SupabaseBackupError.sessionExpired {
            try await refreshAccessTokenIfPossible()
            data = try await getJSON(
                path: "/rest/v1/shifts?select=*&order=start_time.asc",
                authorized: true
            )
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let d = self.isoFractional.date(from: raw) ?? self.isoBasic.date(from: raw) {
                return d
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date \(raw)")
        }
        return try decoder.decode([RemoteShiftRow].self, from: data)
    }

    private func postJSON(path: String, body: [String: Any], authorized: Bool) async throws -> Data {
        var request = try baseRequest(path: path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authorized {
            guard let accessToken else { throw SupabaseBackupError.notSignedIn }
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try throwIfNeeded(response: response, data: data)
        return data
    }

    private func getJSON(path: String, authorized: Bool) async throws -> Data {
        var request = try baseRequest(path: path, method: "GET")
        if authorized {
            guard let accessToken else { throw SupabaseBackupError.notSignedIn }
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try throwIfNeeded(response: response, data: data)
        return data
    }

    private func authorizedRequest(path: String, method: String) throws -> URLRequest {
        guard let accessToken else { throw SupabaseBackupError.notSignedIn }
        var request = try baseRequest(path: path, method: method)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func baseRequest(path: String, method: String) throws -> URLRequest {
        guard let base = SupabaseConfig.projectURL else { throw SupabaseBackupError.notConfigured }
        let root = base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = path.hasPrefix("/") ? path : "/" + path
        guard let url = URL(string: root + suffix) else { throw SupabaseBackupError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func throwIfNeeded(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseBackupError.server(String(localized: "No response from Supabase."))
        }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 { throw SupabaseBackupError.sessionExpired }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = json["msg"] as? String
                ?? json["error_description"] as? String
                ?? json["message"] as? String
                ?? (json["error"] as? String) {
                throw SupabaseBackupError.server(msg)
            }
            throw SupabaseBackupError.server(String(localized: "Supabase error (\(http.statusCode))."))
        }
    }
}

// MARK: - Remote row

private struct RemoteShiftRow: Codable {
    var user_id: String
    var id: String
    var ukg_record_id: String?
    var date: Date
    var start_time: Date
    var end_time: Date
    var job: String
    var location: String?
    var kind: String
    var pay_code: String?
    var notes: String?
    var updated_at: Date

    init(from shift: Shift, userID: String) {
        user_id = userID
        id = shift.id
        ukg_record_id = shift.ukgRecordId
        date = shift.date
        start_time = shift.startTime
        end_time = shift.endTime
        job = shift.job
        location = shift.location
        kind = shift.kind.rawValue
        pay_code = shift.payCode
        notes = shift.notes
        updated_at = Date()
    }

    var asShift: Shift {
        Shift(
            ukgRecordId: ukg_record_id,
            date: date,
            startTime: start_time,
            endTime: end_time,
            job: job,
            location: location,
            kind: ShiftKind(rawValue: kind) ?? .regular,
            payCode: pay_code,
            notes: notes
        )
    }
}

enum SupabaseBackupError: LocalizedError {
    case notConfigured
    case notSignedIn
    case sessionExpired
    case emailConfirmationRequired
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            String(localized: "Add your Supabase URL and anon key in SupabaseConfig.swift first.")
        case .notSignedIn:
            String(localized: "Sign in to cloud backup first.")
        case .sessionExpired:
            String(localized: "Cloud backup session expired. Sign in again.")
        case .emailConfirmationRequired:
            String(localized: "Check your email to confirm the account, or disable Confirm email in Supabase Auth settings.")
        case .server(let message):
            message
        }
    }
}

private extension URL {
    func appending(queryItems: [URLQueryItem]) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.queryItems = (components.queryItems ?? []) + queryItems
        return components.url ?? self
    }
}
