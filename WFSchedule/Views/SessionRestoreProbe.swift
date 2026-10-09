import SwiftUI

/// A hidden copy of the UKG sign-in page, loaded behind the app's own UI so a
/// returning user's still-valid session cookies sign them back in silently — the
/// page finishes loading already past login and this hands the session over, with
/// no sign-in step shown. If there's no valid session it simply never fires, and
/// the sign-in button on Home is the way in.
///
/// Sized to the full screen, not shrunk to a 1x1 point. Confirmed live once
/// already for a different webview in this app (see `SessionManager.keepWindowAttached`):
/// a WKWebView given a degenerate size or `isHidden = true` can leave a modern,
/// JS-driven SPA's own bootstrap/render cycle stalled indefinitely, producing a
/// permanently empty page that never finishes navigating anywhere. Whole Foods'
/// sign-in used to be almost entirely server-side redirects (ForgeRock/OpenAM ->
/// Microsoft), which tolerated a 1x1 probe fine; now that it redirects through an
/// Amazon-hosted login page, a JS-driven silent-SSO check on that page may depend
/// on rendering at a real size the same way the rest of this app's webviews do.
/// Staying invisible to the user is handled by `.background` placing this behind
/// the tab view's own opaque content, not by shrinking or hiding the webview
/// itself — the one approach already proven not to trip that stall.
struct SessionRestoreProbe: View {
    @EnvironmentObject private var sessionManager: SessionManager

    var body: some View {
        UKGLoginWebView(loginURL: UKGEndpoints.loginURL) { webView, cookies in
            sessionManager.handleInteractiveLoginSuccess(webView: webView, cookies: cookies)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
