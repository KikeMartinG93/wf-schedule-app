import SwiftUI
import WebKit

/// Hosts Innerview's own sign-in: it bounces through Amazon's federation to
/// Whole Foods' Microsoft page (TMID@wholefoods.com) and back. The user types
/// their credentials into that page directly — this app never sees them.
///
/// Success is "the page in front of us is Innerview's schedule", judged from its
/// text, not from a cookie or a URL. An unauthenticated load of Innerview briefly
/// finishes on `innerview.amazon.dev` (its shell) before it redirects to sign-in,
/// and a token cookie left over from an earlier session can already be sitting in
/// the store — either would look like success to a host or cookie check and
/// dismiss the sheet before anything was actually signed in.
struct InnerviewLoginWebView: UIViewRepresentable {
    let onAuthenticated: (WKWebView, [HTTPCookie]) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.load(URLRequest(url: InnerviewEndpoints.loginURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onAuthenticated: onAuthenticated)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let onAuthenticated: (WKWebView, [HTTPCookie]) -> Void
        private var reportedSuccess = false
        private var watching = false

        init(onAuthenticated: @escaping (WKWebView, [HTTPCookie]) -> Void) {
            self.onAuthenticated = onAuthenticated
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard webView.url?.host == InnerviewEndpoints.host else { return }
            watchForSchedule(in: webView)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        /// Innerview's page renders after it finishes loading (it's a JS app that
        /// fetches the schedule first), so this keeps looking for a while rather
        /// than judging the moment the load finishes.
        private func watchForSchedule(in webView: WKWebView) {
            guard !reportedSuccess, !watching else { return }
            watching = true
            Task { @MainActor [weak self, weak webView] in
                defer { self?.watching = false }
                for _ in 0..<50 {
                    guard let self, let webView, !self.reportedSuccess else { return }
                    guard webView.url?.host == InnerviewEndpoints.host else { return }
                    if let text = try? await webView.evaluateJavaScript("document.body ? document.body.innerText : ''") as? String,
                       InnerviewScheduleParser.parse(pageText: text).dayCount > 0 {
                        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                        self.reportedSuccess = true
                        self.onAuthenticated(webView, cookies.filter { InnerviewEndpoints.isSessionCookie($0) })
                        return
                    }
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
        }
    }
}
