import Foundation

/// Innerview is Whole Foods' team member app — a read-only mirror of the same
/// UKG schedule, behind Whole Foods' own Microsoft sign-in (TMID@wholefoods.com)
/// instead of the Amazon-hosted UKG Pro login. Its session is first-party to
/// `innerview.amazon.dev` (a JWT plus a refresh token in that host's own cookies),
/// so unlike UKG's federated flow it doesn't depend on a third-party iframe to
/// resume.
enum InnerviewEndpoints {
    static let host = "innerview.amazon.dev"

    /// Where sign-in starts. An unauthenticated load of this bounces through
    /// idp.federate.amazon.com to login.microsoftonline.com and back.
    static let loginURL = URL(string: "https://\(host)/schedule")!

    /// One page that lists roughly eleven weeks (about eight back, two and a
    /// half ahead) in a single continuous list, already expanded to the level
    /// of detail this app needs — no paging or tapping required.
    static let scheduleURL = URL(string: "https://\(host)/schedule/week")!

    /// The JWT Innerview's own JS sets once sign-in finishes. Its presence is
    /// what distinguishes "landed back on Innerview signed in" from "landed on
    /// Innerview's shell a moment before it redirects to sign-in".
    static let tokenCookieName = "innerview.token"

    /// Everything a returning launch needs to resume without typing anything:
    /// Innerview's own cookies, plus the identity provider's (Amazon federate
    /// and Microsoft) so that if Innerview's short-lived token has lapsed, the
    /// bounce through sign-in completes silently on its own. Several of those
    /// are session cookies, which WebKit throws away when the app is killed —
    /// which is why they're saved separately (see `SessionManager`).
    static func isSessionCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
        return domain == host
            || domain.hasSuffix(".\(host)")
            || domain.hasSuffix("federate.amazon.com")
            || domain.hasSuffix("microsoftonline.com")
    }

    static func hasToken(in cookies: [HTTPCookie]) -> Bool {
        cookies.contains { $0.name == tokenCookieName && !$0.value.isEmpty }
    }
}
