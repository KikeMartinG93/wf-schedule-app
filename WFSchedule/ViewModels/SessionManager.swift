import Foundation
import WebKit
import Combine
import UIKit

/// Which sign-in a session came from. Innerview Login is the primary one; the
/// Amazon-hosted UKG Pro sign-in stays as a backup (Settings).
enum SessionBackend: String {
    case innerview
    case ukg
}

enum SessionState: Equatable {
    case loggedOut
    case authenticated
    case needsManualLogin
}

/// Owns the UKG session lifecycle: interactive login (via UKGLoginWebView),
/// cookie storage, and best-effort silent re-login using credentials in the
/// Keychain. If silent re-login fails, the app must fall back to asking the
/// user to log in again — it never has the actual password to retry blindly
/// forever.
///
/// Confirmed live: UKG's session-relay mechanism (ForgeRock/OpenAM) rejects a
/// bare `URLSession` request replaying cookies — it responds 200 with a
/// self-submitting HTML redirect page instead of JSON, because part of what it
/// checks only exists in a real browser context. So this keeps the actual
/// authenticated `WKWebView` alive (not just its cookies) and schedule fetches
/// read directly from that webview's own rendered DOM — see UKGScheduleClient.
///
/// The webview handed in from the interactive login flow lives inside SwiftUI's
/// `LoginView`; the instant login succeeds, `RootView` swaps it out for
/// `ScheduleListView`, and SwiftUI removes the webview's `UIView` from the
/// window. So it's kept alive here by re-parenting it as a subview of the key
/// window (matching the technique HeadlessUKGLogin already used for its own
/// webview) rather than trusting it to remain wherever SwiftUI left it — a
/// `WKWebView` with no window at all is a strictly worse starting point.
///
/// NOTE: this alone was NOT enough to get a working schedule read. Extensive
/// live testing (see UKGScheduleClient's doc comment) found that
/// `document.body` stays permanently empty in this webview regardless of
/// whether it's hidden, moved off-screen, kept on-screen behind the app's own
/// UI, or even left completely undisturbed in SwiftUI's own hierarchy with no
/// reparenting at all — every configuration produced byte-identical empty
/// results. That rules out visibility/throttling as the cause. The real
/// suspect: `fetch()` calls made from JS inside this exact page/origin were
/// separately confirmed to throw — if Whole Foods' own Angular app blocks
/// initial render on its own data-fetch succeeding, the same underlying
/// failure would produce exactly this symptom, independent of visibility.
/// That points at something rejecting in-page network calls generally in this
/// webview context — not something fixable by rearranging views.
///
/// SESSION RESTORE ON LAUNCH (added after the identity provider behind
/// `UKGEndpoints.loginURL` moved from Microsoft to an Amazon-hosted login page):
/// this used to rely entirely on `SessionRestoreProbe` reloading `loginURL` in a
/// hidden webview and hoping two things both held: WKWebView's own on-disk cookie
/// jar still had a valid session cookie after the process was fully killed and
/// relaunched, AND the identity provider would silently complete SSO again with
/// no interaction (the same thing Microsoft's IdP did for a returning user).
/// Confirmed by user report: with the Amazon-hosted IdP that stopped working —
/// every relaunch asked to sign in again, even right after a successful sign-in
/// minutes earlier, and even after `SessionRestoreProbe` was fixed to no longer
/// render at a degenerate size (which was a real bug, just not this one). A
/// prime suspect for the remaining failure is that Amazon's IdP performs its
/// silent-session check through a third-party iframe (a common OIDC
/// `prompt=none` silent-renew pattern) — WKWebView blocks third-party cookies by
/// default (ITP), so that check would always see "not signed in" regardless of
/// what's in the top-level page's own cookie jar, forcing a real interactive
/// prompt every time.
///
/// `attemptCookieRestore` sidesteps needing that federated silent-check to work
/// at all: it saves the actual mykronos.com-domain cookies from the last
/// successful login in the Keychain (this app's own durable storage, not
/// WKWebView's), and on the next launch seeds a fresh webview's cookie jar with
/// them BEFORE loading anything. If those cookies are still valid server-side,
/// the very first request already carries a valid first-party session — no
/// cross-domain redirect chain or third-party iframe involved, so nothing for
/// ITP to block.
@MainActor
final class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published private(set) var state: SessionState = .loggedOut
    @Published private(set) var lastLoginError: String?
    /// True from launch (whenever this device has signed in before) until
    /// `attemptCookieRestore` resolves one way or the other. Lets the UI hold
    /// off on showing "you're signed out" while that check is still running,
    /// instead of flashing it on every single launch before quietly
    /// correcting itself a moment later once the saved cookies check out.
    @Published private(set) var isRestoringSession: Bool = SessionManager.hasSignedInBefore

    /// Which sign-in the current (or last) session used — decides which client
    /// fetches the schedule and which saved cookies a launch tries to resume from.
    @Published private(set) var backend: SessionBackend = SessionManager.preferredBackend

    private var cookies: [HTTPCookie] = []
    private var webView: WKWebView?

    private static let signedInBeforeKey = "hasSignedInBefore"
    private static let backendKey = "sessionBackend"

    /// Innerview Login, unless this device signed in through UKG Pro before
    /// Innerview existed in the app — those keep resuming through UKG until the
    /// user signs in with Innerview.
    static var preferredBackend: SessionBackend {
        if let raw = UserDefaults.standard.string(forKey: backendKey), let stored = SessionBackend(rawValue: raw) {
            return stored
        }
        return hasSignedInBefore ? .ukg : .innerview
    }

    /// True once this device has completed a UKG sign-in and hasn't signed out
    /// since. Used to quietly try restoring the session at launch (UKG's own
    /// cookies usually still hold a valid one) instead of asking to sign in.
    static var hasSignedInBefore: Bool {
        UserDefaults.standard.bool(forKey: signedInBeforeKey)
    }

    func handleInteractiveLoginSuccess(webView: WKWebView, cookies: [HTTPCookie], backend: SessionBackend = .ukg) {
        guard state != .authenticated || backend != self.backend else {
            // Two restore paths can race at launch (SessionRestoreProbe and
            // attemptCookieRestore both try independently) — keep whichever
            // session was established first instead of clobbering it, and don't
            // leak this second webview as an orphaned, still-window-attached subview.
            // (A sign-in through the OTHER backend is a deliberate switch, not a
            // race, so that one goes through and replaces the session.)
            webView.removeFromSuperview()
            return
        }
        if state == .authenticated { self.webView?.removeFromSuperview() }
        Self.keepWindowAttached(webView)
        self.webView = webView
        self.cookies = cookies
        self.backend = backend
        state = .authenticated
        lastLoginError = nil
        UserDefaults.standard.set(true, forKey: Self.signedInBeforeKey)
        UserDefaults.standard.set(backend.rawValue, forKey: Self.backendKey)
        persistCookieSnapshot(from: webView)
    }

    /// Saves the webview's current mykronos.com-domain cookies to the Keychain for
    /// `attemptCookieRestore` to replay on a future launch. Reads the webview's own
    /// live jar rather than trusting whatever cookie list the caller already has —
    /// at the moment login is first detected, cookies the SPA sets during its own
    /// bootstrap (after the page finishes loading) may not exist yet, so this is a
    /// fuller snapshot than what's available right when success fires.
    /// Re-snapshots the live webview's cookies to the Keychain. Called after
    /// every successful schedule sync (see `ScheduleSyncCoordinator`), not
    /// just at login — a session can keep renewing itself silently for days
    /// inside a live webview without the app ever fully restarting, and the
    /// saved snapshot would otherwise still reflect the last actual sign-in.
    /// A relaunch weeks later would then seed `attemptCookieRestore` with a
    /// stale cookie even though the session in memory was fine right up
    /// until the app was killed.
    func persistCurrentSessionSnapshot() {
        guard let webView else { return }
        persistCookieSnapshot(from: webView)
    }

    private func persistCookieSnapshot(from webView: WKWebView) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { allCookies in
            Task { @MainActor in
                let backend = self.backend
                let relevant = allCookies.filter { Self.isSessionCookie($0, for: backend) }
                guard !relevant.isEmpty,
                      let data = try? NSKeyedArchiver.archivedData(withRootObject: relevant, requiringSecureCoding: true)
                else { return }
                KeychainService.setData(data, account: Self.cookieAccount(for: backend))
            }
        }
    }

    private static func cookieAccount(for backend: SessionBackend) -> String {
        switch backend {
        case .innerview: KeychainService.Account.innerviewSessionCookies
        case .ukg: KeychainService.Account.sessionCookies
        }
    }

    private static func isSessionCookie(_ cookie: HTTPCookie, for backend: SessionBackend) -> Bool {
        switch backend {
        case .innerview: InnerviewEndpoints.isSessionCookie(cookie)
        case .ukg: UKGEndpoints.isUKGCookie(cookie)
        }
    }

    private func loadPersistedCookies(for backend: SessionBackend) -> [HTTPCookie]? {
        guard let data = KeychainService.getData(account: Self.cookieAccount(for: backend)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, HTTPCookie.self], from: data) as? [HTTPCookie]
    }

    private var isRestoringCookies = false

    /// Tries to resume a session using cookies saved from the last successful
    /// login instead of relying on the identity provider to silently complete SSO
    /// again on its own — see this type's doc comment for why. Safe to call
    /// whenever; a no-op if there's nothing saved, already authenticated, or
    /// already in progress.
    @discardableResult
    func attemptCookieRestore() async -> Bool {
        guard state != .authenticated else {
            isRestoringSession = false
            return false
        }
        // A second, concurrent call: leave `isRestoringSession` alone and let
        // whichever call is actually in flight be the one that clears it.
        guard !isRestoringCookies else { return false }
        let backend = Self.preferredBackend
        guard let saved = loadPersistedCookies(for: backend), !saved.isEmpty else {
            // Nothing to check — there's no saved session to restore, so the
            // UI can stop waiting and show the sign-in prompt right away.
            isRestoringSession = false
            return false
        }
        isRestoringCookies = true
        defer {
            isRestoringCookies = false
            isRestoringSession = false
        }

        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
        // Same real-size, non-hidden, window-attached technique as every other
        // webview here — see `keepWindowAttached`'s doc comment for why a
        // degenerate size or `isHidden` webview can silently fail to render at all.
        Self.keepWindowAttached(webView)

        let store = webView.configuration.websiteDataStore.httpCookieStore
        for cookie in saved {
            await withCheckedContinuation { continuation in
                store.setCookie(cookie) { continuation.resume() }
            }
        }

        if backend == .innerview {
            // Innerview's own token is short-lived (a day), so the saved identity-
            // provider cookies are what let this quietly get a fresh one if it has
            // lapsed: the load bounces through sign-in and, with those cookies
            // seeded first, comes straight back signed in. Landing on the schedule
            // is the proof; a sign-in page that stays put means the session is gone.
            if case .schedule = await InnerviewPage.load(in: webView, timeout: 25, settle: false) {
                let liveCookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                handleInteractiveLoginSuccess(
                    webView: webView,
                    cookies: liveCookies.filter { InnerviewEndpoints.isSessionCookie($0) },
                    backend: .innerview
                )
                return true
            }
            webView.removeFromSuperview()
            return false
        }

        webView.load(URLRequest(url: UKGEndpoints.loginURL))

        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if webView.url?.host == UKGEndpoints.host, !webView.isLoading {
                let hasPasswordField = (try? await webView.evaluateJavaScript(
                    "!!document.querySelector('input[type=password]')")) as? Bool ?? false
                if !hasPasswordField {
                    let liveCookies: [HTTPCookie] = await withCheckedContinuation { continuation in
                        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies {
                            continuation.resume(returning: $0)
                        }
                    }
                    let relevant = liveCookies.filter { UKGEndpoints.isUKGCookie($0) }
                    if !relevant.isEmpty {
                        handleInteractiveLoginSuccess(webView: webView, cookies: relevant, backend: .ukg)
                        return true
                    }
                }
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        // The saved cookies are no longer valid (server-side expiry, revoked, or
        // this landed on a real login form) — clean up and leave the normal
        // sign-in card as the way in. Not an error: this is expected to happen
        // eventually for every saved session.
        webView.removeFromSuperview()
        return false
    }

    /// Detaches the webview from wherever it currently lives (e.g. a SwiftUI
    /// view about to be torn down) and re-parents it as an off-screen (but NOT
    /// `isHidden`) subview of the key window, so its content process keeps
    /// running normally in the background.
    ///
    /// Confirmed live, in this order:
    ///  1. `removeFromSuperview()` unconditionally before finding a host window
    ///     left the webview attached to NO window at all when the lookup failed
    ///     — worse than doing nothing.
    ///  2. Even once correctly window-attached, setting `isHidden = true`
    ///     resulted in a permanently empty `document.body` (readyState
    ///     "complete", correct URL, but literally zero rendered content) — the
    ///     SPA's own bootstrap/render cycle appears to get throttled while
    ///     `isHidden`. Positioning off-screen while leaving `isHidden = false`
    ///     avoids that throttling without showing anything to the user.
    static func keepWindowAttached(_ webView: WKWebView) {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        guard let host = windows.first(where: { $0.isKeyWindow }) ?? windows.first else {
            return
        }
        webView.removeFromSuperview()
        webView.isHidden = false
        webView.alpha = 1
        let size = host.bounds.size
        webView.frame = CGRect(x: 0, y: 0, width: max(size.width, 1), height: max(size.height, 1))
        // Insert BEHIND all of SwiftUI's own content (index 0) rather than
        // moving off-screen — an on-screen frame, covered by opaque app UI, is
        // indistinguishable from "visible" to WebKit's own throttling
        // heuristics, whereas an off-screen frame was NOT enough to avoid it
        // (confirmed live: still produced a permanently empty document.body).
        host.insertSubview(webView, at: 0)
    }

    /// Explicit opt-in for automatic background refresh. The user re-enters their
    /// UKG credentials here (a native form, separate from the UKG WebView login)
    /// so they can be placed in the Keychain for `attemptSilentReLogin`. Calling
    /// this is a deliberate trade-off the user makes: convenience of automatic
    /// refresh vs. the app holding a replayable copy of their password on-device.
    func enableAutomaticSignIn(username: String, password: String) {
        KeychainService.set(username, account: KeychainService.Account.username)
        KeychainService.set(password, account: KeychainService.Account.password)
    }

    func disableAutomaticSignIn() {
        KeychainService.delete(account: KeychainService.Account.username)
        KeychainService.delete(account: KeychainService.Account.password)
    }

    var hasStoredCredentials: Bool {
        KeychainService.get(account: KeychainService.Account.username) != nil
    }

    /// The live, authenticated webview schedule fetches run inside. `nil` if
    /// there's no session yet or it was torn down (e.g. after logOut).
    func currentWebView() -> WKWebView? {
        webView
    }

    func isSessionValid() -> Bool {
        // Innerview's login is a bundle of cookies from three different sites with
        // wildly different lifetimes, so no one expiry stands for "still signed in";
        // a live webview is the check, and the fetch itself notices a lapsed one.
        if backend == .innerview { return webView != nil }
        // A session cookie with no expiry, or one that hasn't passed its expiry, counts as valid.
        return webView != nil && !cookies.isEmpty && cookies.allSatisfy { cookie in
            guard let expires = cookie.expiresDate else { return true }
            return expires > Date()
        }
    }

    /// Called when a schedule fetch comes back with a session-expired signal.
    /// Attempts a headless re-login using stored credentials; on failure, flips
    /// to `.needsManualLogin` so the UI can prompt and NotificationService can
    /// fire a "login required" alert.
    func attemptSilentReLogin() async -> Bool {
        // Replaying a stored password is only a thing for the UKG Pro sign-in;
        // Innerview resumes from its saved cookies (`attemptCookieRestore`).
        guard backend == .ukg else {
            state = .needsManualLogin
            return false
        }
        guard let username = KeychainService.get(account: KeychainService.Account.username),
              let password = KeychainService.get(account: KeychainService.Account.password) else {
            state = .needsManualLogin
            return false
        }

        do {
            let result = try await HeadlessUKGLogin.login(username: username, password: password)
            Self.keepWindowAttached(result.webView)
            self.webView = result.webView
            self.cookies = result.cookies
            state = .authenticated
            lastLoginError = nil
            persistCookieSnapshot(from: result.webView)
            return true
        } catch {
            state = .needsManualLogin
            lastLoginError = error.localizedDescription
            return false
        }
    }

    func logOut() {
        webView?.removeFromSuperview()
        webView = nil
        cookies = []
        state = .loggedOut
        UserDefaults.standard.set(false, forKey: Self.signedInBeforeKey)
        KeychainService.delete(account: KeychainService.Account.username)
        KeychainService.delete(account: KeychainService.Account.password)
        KeychainService.delete(account: KeychainService.Account.sessionCookies)
        KeychainService.delete(account: KeychainService.Account.innerviewSessionCookies)
        UserDefaults.standard.removeObject(forKey: Self.backendKey)
        backend = Self.preferredBackend
        WKWebsiteDataStore.default().removeData(
            ofTypes: [WKWebsiteDataTypeCookies],
            modifiedSince: .distantPast,
            completionHandler: {}
        )
    }
}
