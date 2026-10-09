import Foundation
import WebKit
import UIKit

enum HeadlessLoginError: LocalizedError {
    case timedOut
    case formNotFound
    case rejected

    var errorDescription: String? {
        switch self {
        case .timedOut: String(localized: "UKG did not respond in time (possibly waiting on a two-factor prompt this app can't complete on its own).")
        case .formNotFound: String(localized: "Could not locate the sign-in form.")
        case .rejected: String(localized: "The stored credentials were rejected.")
        }
    }
}

/// Drives a hidden WKWebView through the real Whole Foods sign-in flow to attempt
/// a silent re-login when the session cookie has expired.
///
/// Confirmed live (as of the Microsoft-hosted identity provider): this is NOT a
/// single page with both a username and password field. It was Whole Foods'
/// multi-step SSO chain of the time:
///   1. `UKGEndpoints.loginURL` redirects to a ForgeRock/OpenAM page (still on a
///      *.mykronos.com host) showing only a username/email field + "Next".
///   2. That redirects to `login.microsoftonline.com` (Entra ID / Azure AD),
///      entirely off the mykronos.com domain, which shows only the password field.
///   3. Entra may then show an MFA prompt (push/OTP) — this app has no way to
///      complete that on its own, so that case is expected to time out into
///      `.timedOut` and fall back to asking the user to sign in interactively.
/// The identity provider has since moved to an Amazon-hosted login page — the step
/// structure above is no longer confirmed live and needs re-verifying against the
/// real flow. `submitUsernameStep`/`submitPasswordStep`'s selectors are generic
/// (`input[type=text|email]`, `input[type=password]`) rather than hard-coded to
/// Microsoft's markup, so this may well still work unmodified, but that's
/// unverified, not confirmed. This reuses the real pages (rather than talking to
/// an undocumented API) so it stays compatible with however each step is
/// implemented, and never has to reverse-engineer the actual auth protocol.
@MainActor
enum HeadlessUKGLogin {
    /// The returned `webView` is kept attached (behind the app's own opaque UI,
    /// not hidden) to the key window rather than torn down — schedule fetches
    /// after a silent re-login run as `fetch()` calls inside this same webview
    /// (see UKGScheduleClient), the same reason the interactive login's webview
    /// is kept alive by SessionManager.
    static func login(username: String, password: String) async throws -> (webView: WKWebView, cookies: [HTTPCookie]) {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif
        // NOT `isHidden = true` / a `.zero` frame: confirmed live elsewhere in this
        // app (see `SessionManager.keepWindowAttached`) that a WKWebView given
        // either one can leave a modern JS-driven SPA's bootstrap/render cycle
        // stalled indefinitely — `document.body` stays empty forever, which here
        // would mean `waitForField` never finds the sign-in form and every
        // silent re-login attempt times out. Reusing the same window-attached,
        // real-size, non-hidden technique already proven not to trip that stall.
        SessionManager.keepWindowAttached(webView)

        do {
            webView.load(URLRequest(url: UKGEndpoints.loginURL))
            try await waitForLoad(webView)

            try await submitUsernameStep(webView, username: username)
            try await submitPasswordStep(webView, password: password)

            try await waitForLandingOnUKGHost(webView)

            let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            let relevant = cookies.filter { UKGEndpoints.isUKGCookie($0) }
            guard !relevant.isEmpty else { throw HeadlessLoginError.rejected }
            return (webView, relevant)
        } catch {
            webView.removeFromSuperview()
            throw error
        }
    }

    /// Fills whichever step is currently showing. If a password field is already
    /// present (some IdPs do show both fields together), this fills both and
    /// submits in one go, skipping the separate password step entirely.
    private static func submitUsernameStep(_ webView: WKWebView, username: String) async throws {
        try await waitForField(webView, selector: "input[type=text], input[type=email], input[name*=user i], #username", timeout: 15)

        let script = """
        (function() {
            const userField = document.querySelector('input[type=text], input[type=email], input[name*=user i], #username');
            if (!userField) { return 'missing'; }
            userField.value = \(jsStringLiteral(username));
            userField.dispatchEvent(new Event('input', { bubbles: true }));
            const passField = document.querySelector('input[type=password]');
            if (passField) {
                return 'has-password-too';
            }
            const form = userField.closest('form');
            if (form) { form.requestSubmit ? form.requestSubmit() : form.submit(); return 'submitted'; }
            const nextBtn = document.querySelector('button[type=submit], input[type=submit], button');
            if (nextBtn) { nextBtn.click(); return 'submitted'; }
            return 'missing';
        })();
        """
        let result = try await webView.evaluateJavaScript(script) as? String
        guard result == "submitted" || result == "has-password-too" else {
            throw HeadlessLoginError.formNotFound
        }
    }

    private static func submitPasswordStep(_ webView: WKWebView, password: String) async throws {
        try await waitForField(webView, selector: "input[type=password]", timeout: 15)

        let script = """
        (function() {
            const passField = document.querySelector('input[type=password]');
            if (!passField) { return 'missing'; }
            passField.value = \(jsStringLiteral(password));
            passField.dispatchEvent(new Event('input', { bubbles: true }));
            const form = passField.closest('form');
            if (form) { form.requestSubmit ? form.requestSubmit() : form.submit(); return 'submitted'; }
            const submitBtn = document.querySelector('button[type=submit], input[type=submit]');
            if (submitBtn) { submitBtn.click(); return 'submitted'; }
            return 'missing';
        })();
        """
        let result = try await webView.evaluateJavaScript(script) as? String
        guard result == "submitted" else { throw HeadlessLoginError.formNotFound }
    }

    private static func jsStringLiteral(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return "'\(escaped)'"
    }

    private static func waitForLoad(_ webView: WKWebView, timeout: TimeInterval = 15) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while webView.isLoading, Date() < deadline {
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        if Date() >= deadline { throw HeadlessLoginError.timedOut }
    }

    private static func waitForField(_ webView: WKWebView, selector: String, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        let checkScript = "!!document.querySelector('\(selector)')"
        while Date() < deadline {
            if let present = try? await webView.evaluateJavaScript(checkScript) as? Bool, present {
                return
            }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        throw HeadlessLoginError.formNotFound
    }

    /// Mirrors the interactive login's detector (see UKGLoginWebView): confirmed
    /// live that an unauthenticated request never settles on `UKGEndpoints.host`,
    /// so a completed load parked there is sufficient proof of success. If Entra
    /// shows an MFA prompt instead, the webview never reaches that host and this
    /// times out into `.timedOut`, which is the correct outcome — this app can't
    /// complete an MFA challenge on its own.
    private static func waitForLandingOnUKGHost(_ webView: WKWebView, timeout: TimeInterval = 25) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if webView.url?.host == UKGEndpoints.host, !webView.isLoading {
                return
            }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        throw HeadlessLoginError.timedOut
    }
}
