import Foundation

enum AppConfig {
    static let supabaseURL: String = {
        let host = Bundle.main.object(forInfoDictionaryKey: "SupabaseHost") as? String ?? ""
        return "https://\(host)"
    }()
    static let supabaseAnonKey = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String ?? ""
    static let supabaseAvatarBucket = Bundle.main.object(forInfoDictionaryKey: "SupabaseAvatarBucket") as? String ?? "Avatar"
    static let webAppURL = Bundle.main.object(forInfoDictionaryKey: "WebAppURL") as? String ?? ""
}
