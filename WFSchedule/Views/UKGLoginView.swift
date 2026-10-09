import SwiftUI

/// The WKWebView login below is the ONLY place the user's UKG password is ever
/// entered — it goes straight into UKG's own page and this app never sees it.
/// That's intentionally incompatible with silent re-login, which needs a stored
/// password to replay. Automatic background refresh is therefore a separate,
/// explicit opt-in (AutoSignInSettingsView) where the user re-types their
/// credentials into a native form specifically so they can be placed in the
/// Keychain — not something this screen does implicitly.
/// The UKG Pro sign-in (through Amazon), kept as the backup to Innerview Login —
/// reached from Settings. Dismisses itself once the session becomes authenticated.
struct UKGLoginView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(baseOpacity: 0.48)

                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Sign in with UKG Pro", systemImage: "lock.shield")
                            .font(.headline)
                        Text("Your credentials go directly into UKG's own sign-in page below — this app never sees them.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let error = sessionManager.lastLoginError {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(ThemeManager.shared.highContrast ? Color.primary : Color.red)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
                    .highContrastOutline(cornerRadius: 20)
                    .padding(.horizontal)
                    .padding(.top, 12)

                    UKGLoginWebView(loginURL: UKGEndpoints.loginURL) { webView, cookies in
                        sessionManager.handleInteractiveLoginSuccess(webView: webView, cookies: cookies, backend: .ukg)
                    }
                    .clipShape(.rect(cornerRadius: 24))
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .onChange(of: sessionManager.state) { _, newState in
                if newState == .authenticated { dismiss() }
            }
            .navigationTitle("Sign in with UKG Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
