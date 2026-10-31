import SwiftUI

/// Sign-in sheet presented over the calendar. The web view below is
/// the ONLY place the team member password is ever entered — it goes straight into
/// the sign-in page and this app never sees it.
/// `RootView` or this view dismisses this as soon as the session becomes authenticated.
struct LoginView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground(baseOpacity: 0.48)

                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Sign in with Amazon", systemImage: "lock.shield")
                            .font(.headline)
                        Text("Sign in with your Whole Foods team member account. Your credentials go directly into the sign-in page below — this app never sees them.")
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
                        sessionManager.handleInteractiveLoginSuccess(webView: webView, cookies: cookies)
                    }
                    .clipShape(.rect(cornerRadius: 24))
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .onChange(of: sessionManager.state) { _, newState in
                if newState == .authenticated { dismiss() }
            }
            .navigationTitle("Sign in with Amazon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        DemoMode.set(true)
                        dismiss()
                    } label: {
                        Label("Demo", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
    }
}
