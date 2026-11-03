import Foundation

/// Supabase project credentials for optional cloud shift backups.
/// Paste your Project URL and anon/public key from Supabase → Settings → API.
/// Never put the service-role key in the app.
enum SupabaseConfig {
    /// e.g. https://xxxx.supabase.co
    static let projectURLString = "https://sghfwuxctnptjbiutvuo.supabase.co"

    /// anon / public key (safe in the client; RLS enforces isolation).
    static let anonKey = "sb_publishable_vC7B1PZe0skJw-kDOWPmmA_wClovGhx"

    static var isConfigured: Bool {
        !projectURLString.contains("YOUR_SUPABASE")
            && !anonKey.contains("YOUR_SUPABASE")
            && URL(string: projectURLString) != nil
            && !anonKey.isEmpty
    }

    static var projectURL: URL? {
        URL(string: projectURLString)
    }
}
