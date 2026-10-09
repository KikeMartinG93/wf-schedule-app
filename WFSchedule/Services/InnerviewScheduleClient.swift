import Foundation
import WebKit

/// Loads Innerview's week view in the already-signed-in webview and reads the
/// rendered text — see `InnerviewScheduleParser` for why the page's text and not
/// its private API.
@MainActor
final class InnerviewScheduleClient: ScheduleFetching {
    private let webView: WKWebView

    init(webView: WKWebView) {
        self.webView = webView
    }

    func fetchShifts() async throws -> [Shift] {
        switch await InnerviewPage.load(in: webView, timeout: 22, settle: true) {
        case .schedule(let result):
            return result.shifts
        case .signedOut:
            throw UKGClientError.sessionExpired
        case .timedOut:
            throw UKGClientError.decodingFailed
        }
    }
}

/// Loading and reading the schedule page, shared by the sync (`InnerviewScheduleClient`)
/// and by resuming a saved session at launch (`SessionManager.attemptCookieRestore`).
@MainActor
enum InnerviewPage {
    enum Outcome {
        case schedule(InnerviewScheduleParser.Result)
        case signedOut
        case timedOut
    }

    /// `settle` waits for the page text to stop changing before trusting it. The
    /// list can briefly render every day as "No scheduled shifts" before its data
    /// arrives, and mistaking that for a real empty schedule would look like every
    /// shift being removed — so an empty-looking page has to hold still much longer
    /// than one with shifts on it before it's believed.
    static func load(in webView: WKWebView, timeout: TimeInterval, settle: Bool) async -> Outcome {
        // A reload throws away every JS global, so this marker being gone is proof
        // the text being read belongs to the new document, not the one it replaced.
        _ = try? await webView.evaluateJavaScript("window.__wfLoadMarker = true")
        webView.load(URLRequest(url: InnerviewEndpoints.scheduleURL, cachePolicy: .reloadIgnoringLocalCacheData))

        let deadline = Date().addingTimeInterval(timeout)
        var lastText: String?
        var stablePolls = 0
        var signedOutPolls = 0
        var latest: InnerviewScheduleParser.Result?

        while Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 400_000_000)

            // Parked on a sign-in page for a couple of seconds is the session being
            // gone; passing through one mid-redirect is not.
            if isOnSignInPage(webView) {
                signedOutPolls += 1
                if signedOutPolls >= 5 { return .signedOut }
                continue
            }
            signedOutPolls = 0

            let isOldDocument = (try? await webView.evaluateJavaScript("window.__wfLoadMarker === true")) as? Bool == true
            guard !isOldDocument,
                  let text = (try? await webView.evaluateJavaScript("document.body ? document.body.innerText : ''")) as? String
            else { continue }

            let result = InnerviewScheduleParser.parse(pageText: text)
            guard result.dayCount > 0 else {
                lastText = nil
                stablePolls = 0
                continue
            }
            latest = result
            if !settle { return .schedule(result) }

            if text == lastText { stablePolls += 1 } else { stablePolls = 0; lastText = text }
            if stablePolls >= (result.shifts.isEmpty ? 8 : 2) { return .schedule(result) }
        }

        if let latest, !latest.shifts.isEmpty, !isOnSignInPage(webView) { return .schedule(latest) }
        return isOnSignInPage(webView) ? .signedOut : .timedOut
    }

    private static func isOnSignInPage(_ webView: WKWebView) -> Bool {
        guard let url = webView.url, let host = url.host else { return false }
        if host != InnerviewEndpoints.host { return !webView.isLoading }
        return url.path.hasPrefix("/not-authorized")
    }
}
