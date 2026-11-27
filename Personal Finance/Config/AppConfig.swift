import Foundation

enum AppConfig {
    static let supabaseURL: String = {
        let host = Bundle.main.object(forInfoDictionaryKey: "SupabaseHost") as? String ?? ""
        return "https://\(host)"
    }()
    static let supabaseAnonKey = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String ?? ""
    static let supabaseAvatarBucket = Bundle.main.object(forInfoDictionaryKey: "SupabaseAvatarBucket") as? String ?? "Avatar"

    /// Where the password-reset email sends the user back to. The scheme is registered under
    /// CFBundleURLTypes in Info.plist, and the full URL must be in Supabase Auth's redirect allow list.
    static let passwordResetRedirectURL = URL(string: "dev.nghiabui.personalfinance://reset-password")!
}
