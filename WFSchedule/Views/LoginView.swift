import SwiftUI

/// Innerview Login, presented as a sheet over the calendar. The web view below is
/// the ONLY place the team member password is ever entered — it goes straight into
/// Innerview's own sign-in page and this app never sees it, which is why there's
/// no way to replay it silently; a returning launch resumes from saved cookies
/// instead (see `SessionManager.attemptCookieRestore`). `MainTabView` dismisses
/// this as soon as the session becomes authenticated.
struct LoginView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(baseOpacity: 0.48)

                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Innerview Login", systemImage: "lock.shield")
                            .font(.headline)
                        Text("Sign in with your Whole Foods team member account. Your credentials go directly into Innerview's own sign-in page below — this app never sees them.")
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

                    InnerviewLoginWebView { webView, cookies in
                        sessionManager.handleInteractiveLoginSuccess(webView: webView, cookies: cookies, backend: .innerview)
                    }
                    .clipShape(.rect(cornerRadius: 24))
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .navigationTitle("Innerview Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            DemoMode.set(true)
                            dismiss()
                        } label: {
                            Label("Demo Mode", systemImage: "sparkles")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.body.weight(.medium))
                            .accessibilityLabel("Options")
                    }
                }
            }
        }
    }
}
