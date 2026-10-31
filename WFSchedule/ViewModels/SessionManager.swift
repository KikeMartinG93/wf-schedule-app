import Foundation
import WebKit
import Combine
import UIKit

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
/// SESSION RESTORE ON LAUNCH:
/// `attemptCookieRestore` saves the actual mykronos.com-domain cookies from the
/// last successful login in the Keychain (this app's own durable storage, not
/// WKWebView's), and on the next launch seeds a fresh webview's cookie jar with
/// them BEFORE loading anything. If those cookies are still valid server-side,
/// the very first request already carries a valid first-party session.
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

    private var cookies: [HTTPCookie] = []
    private var webView: WKWebView?
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?

    init() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleAppDidEnterBackground()
            }
        }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleAppWillEnterForeground()
            }
        }
    }

    deinit {
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
        if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
    }

    private static let signedInBeforeKey = "hasSignedInBefore"

    /// True once this device has completed a sign-in and hasn't signed out
    /// since. Used to quietly try restoring the session at launch (UKG's own
    /// cookies usually still hold a valid one) instead of asking to sign in.
    static var hasSignedInBefore: Bool {
        UserDefaults.standard.bool(forKey: signedInBeforeKey)
    }

    func handleInteractiveLoginSuccess(webView: WKWebView, cookies: [HTTPCookie]) {
        guard state != .authenticated else {
            // Two restore paths can race at launch (SessionRestoreProbe and
            // attemptCookieRestore both try independently) — keep whichever
            // session was established first instead of clobbering it, and don't
            // leak this second webview as an orphaned, still-window-attached subview.
            webView.removeFromSuperview()
            return
        }
        if state == .authenticated { self.webView?.removeFromSuperview() }
        Self.keepWindowAttached(webView)
        self.webView = webView
        self.cookies = cookies
        state = .authenticated
        lastLoginError = nil
        UserDefaults.standard.set(true, forKey: Self.signedInBeforeKey)
        persistCookieSnapshot(from: webView)
    }

    /// Saves the webview's current mykronos.com-domain cookies to the Keychain for
    /// `attemptCookieRestore` to replay on a future launch. Reads the webview's own
    /// live jar rather than trusting whatever cookie list the caller already has.
    /// Re-snapshots the live webview's cookies to the Keychain after
    /// every successful schedule sync (see `ScheduleSyncCoordinator`), not
    /// just at login.
    func persistCurrentSessionSnapshot() {
        guard let webView else { return }
        persistCookieSnapshot(from: webView)
    }

    private func persistCookieSnapshot(from webView: WKWebView) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { allCookies in
            Task { @MainActor in
                let relevant = allCookies.filter { UKGEndpoints.isUKGCookie($0) }
                guard !relevant.isEmpty,
                      let data = try? NSKeyedArchiver.archivedData(withRootObject: relevant, requiringSecureCoding: true)
                else { return }
                KeychainService.setData(data, account: KeychainService.Account.sessionCookies)
            }
        }
    }

    private func loadPersistedCookies() -> [HTTPCookie]? {
        guard let data = KeychainService.getData(account: KeychainService.Account.sessionCookies) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, HTTPCookie.self], from: data) as? [HTTPCookie]
    }

    private var isRestoringCookies = false

    /// Tries to resume a session using cookies saved from the last successful
    /// login instead of relying on the identity provider to silently complete SSO
    /// again on its own. Safe to call whenever; a no-op if there's nothing saved,
    /// already authenticated, or already in progress.
    @discardableResult
    func attemptCookieRestore() async -> Bool {
        // Do not attempt cookie restore if the app is in the background.
        // Loading web pages in the background risks 0x8BADF00D watchdog hangs.
        guard UIApplication.shared.applicationState != .background else {
            return false
        }
        guard state != .authenticated else {
            isRestoringSession = false
            return false
        }
        // A second, concurrent call: leave `isRestoringSession` alone and let
        // whichever call is actually in flight be the one that clears it.
        guard !isRestoringCookies else { return false }
        guard let saved = loadPersistedCookies(), !saved.isEmpty else {
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

        let configuration = WKWebViewConfiguration.scheduleAppConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
        // Same real-size, non-hidden, window-attached technique as every other
        // webview here — see `keepWindowAttached`'s doc comment.
        Self.keepWindowAttached(webView)

        let store = webView.configuration.websiteDataStore.httpCookieStore
        for cookie in saved {
            await withCheckedContinuation { continuation in
                store.setCookie(cookie) { continuation.resume() }
            }
        }

        webView.load(URLRequest(url: UKGEndpoints.loginURL))

        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if UIApplication.shared.applicationState == .background {
                webView.stopLoading()
                webView.removeFromSuperview()
                return false
            }
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
                        handleInteractiveLoginSuccess(webView: webView, cookies: relevant)
                        return true
                    }
                }
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        // The saved cookies are no longer valid (server-side expiry, revoked, or
        // this landed on a real login form) — clean up and leave the normal
        // sign-in card as the way in.
        webView.removeFromSuperview()
        return false
    }

    /// Detaches the webview from wherever it currently lives (e.g. a SwiftUI
    /// view about to be torn down) and re-parents it as an off-screen (but NOT
    /// `isHidden`) subview of the key window, so its content process keeps
    /// running normally in the background.
    static func keepWindowAttached(_ webView: WKWebView) {
        guard UIApplication.shared.applicationState != .background else {
            return
        }
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
            .flatMap { $0.windows }
        guard let host = windows.first(where: { $0.isKeyWindow }) ?? windows.first else {
            return
        }
        webView.removeFromSuperview()
        webView.isHidden = false
        webView.alpha = 1
        let size = host.bounds.size
        webView.frame = CGRect(x: 0, y: 0, width: max(size.width, 1), height: max(size.height, 1))
        host.insertSubview(webView, at: 0)
    }

    func handleAppDidEnterBackground() {
        webView?.stopLoading()
        webView?.removeFromSuperview()
    }

    func handleAppWillEnterForeground() {
        guard state == .authenticated, let webView else { return }
        Self.keepWindowAttached(webView)
    }

    /// Explicit opt-in for automatic background refresh. The user re-enters their
    /// UKG credentials here (a native form, separate from the UKG WebView login)
    /// so they can be placed in the Keychain for `attemptSilentReLogin`.
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
        webView != nil && !cookies.isEmpty && cookies.allSatisfy { cookie in
            guard let expires = cookie.expiresDate else { return true }
            return expires > Date()
        }
    }

    /// Called when a schedule fetch comes back with a session-expired signal.
    /// Attempts a headless re-login using stored credentials; on failure, flips
    /// to `.needsManualLogin` so the UI can prompt and NotificationService can
    /// fire a "login required" alert.
    func attemptSilentReLogin() async -> Bool {
        guard let username = KeychainService.get(account: KeychainService.Account.username),
              let password = KeychainService.get(account: KeychainService.Account.password) else {
            state = .needsManualLogin
            return false
        }

        do {
            let result = try await HeadlessUKGLogin.login(username: username, password: password)
            if UIApplication.shared.applicationState != .background {
                Self.keepWindowAttached(result.webView)
            }
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
        WKWebsiteDataStore.default().removeData(
            ofTypes: [WKWebsiteDataTypeCookies],
            modifiedSince: .distantPast,
            completionHandler: {}
        )
    }
}

extension WKWebViewConfiguration {
    /// Configures a `WKWebViewConfiguration` suitable for this app's internal,
    /// headless, and authentication flows, disabling Screen Time tracking hooks
    /// that can cause synchronous XPC hangs and 0x8BADF00D watchdog terminations
    /// during background transitions.
    static func scheduleAppConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        if #available(iOS 16.0, *) {
            configuration.showsSystemScreenTimeBlockingView = false
        }
        let selPref = Selector(("_setScreenTimeEnabled:"))
        let selPublic = Selector(("setScreenTimeEnabled:"))
        if configuration.preferences.responds(to: selPref) || configuration.preferences.responds(to: selPublic) {
            configuration.preferences.setValue(false, forKey: "screenTimeEnabled")
        }
        return configuration
    }
}
