import Foundation

enum AppConfig {
    static let supabaseURL: String = {
        let host = Bundle.main.object(forInfoDictionaryKey: "SupabaseHost") as? String ?? ""
        return "https://\(host)"
    }()
    static let supabaseAnonKey = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String ?? ""
}
