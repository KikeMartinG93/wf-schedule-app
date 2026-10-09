import SwiftUI
import WebKit

/// Hosts the real WholeFoods/UKG SSO login page. The user types their credentials
/// directly into UKG's own page — or, as is actually the case for Whole Foods, an
/// external identity provider it redirects to entirely off-domain (confirmed live:
/// wfminc-sso.prd.mykronos.com -> a ForgeRock/OpenAM host on *.mykronos.com for a
/// "which account" step -> login.microsoftonline.com for the real password entry).
/// This app never sees the password field's contents.
///
/// An earlier version of this detector watched the DOM for a password field
/// disappearing while parked on a mykronos.com page. That's wrong for this real
/// flow: the password field only ever appears on login.microsoftonline.com, which
/// is intentionally excluded (to avoid firing the instant an SSO redirect starts,
/// before the user has typed anything) — so it can disappear/reappear there all it
/// wants and never signal anything, and it never reappears on a mykronos.com page
/// at all, so the "seen once, now gone" condition can never be satisfied. Confirmed
/// live: after a real successful sign-in landing back on the actual My Calendar
/// page, the app stayed stuck on the login screen indefinitely.
///
/// Instead: confirmed by testing (both loading `loginURL` cold and hitting the
/// schedule API cold), an unauthenticated request to `UKGEndpoints.host` always
/// gets redirected away before anything finishes loading there — it never settles.
/// So a completed page load whose URL host is exactly `UKGEndpoints.host` is, by
/// itself, sufficient proof of an authenticated session. A same-page password-field
/// check is kept only as a defense-in-depth sanity check in case that ever changes.
struct UKGLoginWebView: UIViewRepresentable {
    let loginURL: URL
    let onAuthenticated: (WKWebView, [HTTPCookie]) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        // Without this, the webview is invisible to Safari's Web Inspector even
        // with Developer Mode on — that toggle only covers Safari's own tabs,
        // not a third-party app's WKWebView. DEBUG-only: it lets anyone with a
        // cable inspect the page, so it has no business being on in a build
        // anyone but a developer runs.
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif
        webView.navigationDelegate = context.coordinator
        // Some SSO providers open their form in a popup (window.open / target=_blank);
        // without a UI delegate those requests are silently dropped and the button
        // appears to do nothing. Route them into the same webview instead.
        webView.uiDelegate = context.coordinator
        webView.load(URLRequest(url: loginURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onAuthenticated: onAuthenticated)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let onAuthenticated: (WKWebView, [HTTPCookie]) -> Void
        private var reportedSuccess = false

        init(onAuthenticated: @escaping (WKWebView, [HTTPCookie]) -> Void) {
            self.onAuthenticated = onAuthenticated
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard webView.url?.host == UKGEndpoints.host else { return }
            confirmNoPasswordFieldThenReport(webView)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // No target=_blank support: load the popup's URL in the same webview.
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        private func confirmNoPasswordFieldThenReport(_ webView: WKWebView) {
            guard !reportedSuccess else { return }
            webView.evaluateJavaScript("!!document.querySelector('input[type=password]')") { [weak self] result, _ in
                guard let self, !self.reportedSuccess else { return }
                if (result as? Bool) == true { return }
                self.reevaluateCookies(webView)
            }
        }

        private func reevaluateCookies(_ webView: WKWebView) {
            guard !reportedSuccess else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.reportedSuccess else { return }
                let relevant = cookies.filter { UKGEndpoints.isUKGCookie($0) }
                guard !relevant.isEmpty else { return }
                self.reportedSuccess = true
                DispatchQueue.main.async {
                    self.onAuthenticated(webView, relevant)
                }
            }
        }
    }
}

enum UKGEndpoints {
    static let host = "wfminc-sso.prd.mykronos.com"
    static let tenantId = "wfminc_prd_02"
    static let loginURL = URL(string: "https://\(host)/wfd/ess/myschedule?tenantId=\(tenantId)#/")!

    static func isUKGCookie(_ cookie: HTTPCookie) -> Bool {
        cookie.domain.contains("mykronos.com")
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    /// Confirmed real path: `/myschedule/events`. The query params below (date
    /// range as yyyy-MM-dd) match UKG WFD ESS's typical calendar-events contract;
    /// verify against the exact captured request URL and adjust param names here
    /// if the live call 400s.
    static func scheduleEndpoint(startDate: Date, endDate: Date) -> URL {
        var components = URLComponents(string: "https://\(host)/myschedule/events")!
        components.queryItems = [
            URLQueryItem(name: "startDate", value: dayFormatter.string(from: startDate)),
            URLQueryItem(name: "endDate", value: dayFormatter.string(from: endDate)),
            URLQueryItem(name: "tenantId", value: tenantId)
        ]
        return components.url!
    }
}
