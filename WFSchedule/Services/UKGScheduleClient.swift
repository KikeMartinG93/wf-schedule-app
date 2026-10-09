import Foundation
import WebKit

enum UKGClientError: LocalizedError {
    case sessionExpired
    case badResponse(Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .sessionExpired: String(localized: "UKG session expired.")
        case .badResponse(let code): String(localized: "UKG returned an unexpected response (\(code)).")
        case .decodingFailed: String(localized: "Could not parse the UKG schedule response.")
        }
    }
}

/// Fetches the authenticated user's schedule from UKG via `POST /myschedule/events`.
///
/// This is the real request, captured via a HAR export from a genuine
/// authenticated session (Safari Web Inspector on a real device) — not
/// reconstructed by guessing. Two things earlier attempts got wrong:
///  1. It's a POST with a JSON body, not a GET with query params — there are no
///     query params at all.
///  2. It requires an `X-XSRF-TOKEN` header, whose value comes from the
///     `XSRF-TOKEN` cookie (a standard double-submit-cookie CSRF pattern).
///
/// REVERTED (per user request) from a multi-window pagination scheme back to
/// this single request. The pagination version (paging through ~13-day windows
/// to try to reach further into the posted schedule) caused a crash going into
/// the List tab and, separately, could end up showing no shifts at all — most
/// likely because each window ran its own `URLSession` request outside the
/// webview, so the rotating `XSRF-TOKEN` cookie for windows after the first
/// went stale, and/or the repeated sequential networking during a tab
/// transition triggered the crash. This single-request version is the one
/// that was confirmed working end-to-end against a real account.
///
/// `@MainActor`-isolated because `currentCookies()` reaches into
/// `webView.configuration.websiteDataStore.httpCookieStore` — WKWebView and
/// everything hanging off it are documented main-thread-only; calling into
/// it from a background executor (which is where this would otherwise run,
/// since nothing upstream was forcing a hop) is undefined behavior, not just
/// a lint nitpick. The Xcode 27 SDK actually flags this now (a compiler
/// warning, not yet a hard error), which is how this was caught. Every other
/// WKWebView-touching type in this codebase (`HeadlessUKGLogin`,
/// `SessionManager`) is already `@MainActor` for the same reason — this was
/// the one exception.
@MainActor
final class UKGScheduleClient {
    private let webView: WKWebView

    init(webView: WKWebView) {
        self.webView = webView
    }

    func fetchSchedule(daysAhead: Int = 21) async throws -> [Shift] {
        let cookies = try await waitForXSRFCookie()
        let xsrfToken = cookies.first(where: { $0.name == "XSRF-TOKEN" })!.value

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.timeZone = .current
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: daysAhead, to: start)!

        let requestBody = WFScheduleEventsRequest(
            data: .init(dateSpan: .init(start: dayFormatter.string(from: start), end: dayFormatter.string(from: end)))
        )

        let url = URL(string: "https://\(UKGEndpoints.host)/myschedule/events")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(xsrfToken, forHTTPHeaderField: "X-XSRF-TOKEN")
        request.setValue("phone", forHTTPHeaderField: "device-type")
        request.setValue("ess", forHTTPHeaderField: "page")
        request.setValue("https://\(UKGEndpoints.host)", forHTTPHeaderField: "Origin")
        request.setValue(UKGEndpoints.loginURL.absoluteString, forHTTPHeaderField: "Referer")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        HTTPCookieStorage.shared.setCookies(cookies, for: url, mainDocumentURL: nil)
        let session = URLSession(configuration: config)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UKGClientError.badResponse(-1) }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw UKGClientError.sessionExpired
        }
        guard (200...299).contains(http.statusCode) else {
            throw UKGClientError.badResponse(http.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(WFScheduleEventsResponse.self, from: data)
            return WFScheduleMapper.shifts(from: decoded)
        } catch {
            throw UKGClientError.decodingFailed
        }
    }

    private func currentCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    /// The XSRF-TOKEN cookie is set by the SPA's OWN bootstrap calls (config,
    /// permissions, etc.) after the My Calendar page loads — not necessarily by
    /// the moment login succeeds. Confirmed live: calling this right after login
    /// detection fires can race ahead of that cookie ever being set, which
    /// previously threw `sessionExpired` immediately and triggered a real login
    /// <-> home screen bounce loop (a false re-login, not an actual expired
    /// session). Poll briefly instead of failing on the very first miss.
    private func waitForXSRFCookie(timeout: TimeInterval = 12) async throws -> [HTTPCookie] {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let cookies = await currentCookies()
            if cookies.contains(where: { $0.name == "XSRF-TOKEN" }) {
                return cookies
            }
            if Date() >= deadline {
                throw UKGClientError.sessionExpired
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
    }
}
