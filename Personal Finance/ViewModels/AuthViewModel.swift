import Foundation
import SwiftUI
import Supabase

enum AuthState {
    case loading, authenticated, unauthenticated
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var authState: AuthState = .loading
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var isUpdating = false
    @Published var errorMessage: String?
    @Published var updateError: String?

    private let auth = SupabaseService.shared.client.auth
    private let storage = SupabaseService.shared.client.storage

    init() {
        Task { await observeAuthState() }
    }

    // MARK: - Computed profile info

    var displayName: String {
        metaString("full_name") ?? currentUser?.email?.components(separatedBy: "@").first ?? "User"
    }

    var avatarURL: URL? {
        guard let s = metaString("avatar_url") else { return nil }
        return URL(string: s)
    }

    var userEmail: String { currentUser?.email ?? "" }
    var userPhone: String { currentUser?.phone ?? "" }

    private func metaString(_ key: String) -> String? {
        guard let json = currentUser?.userMetadata[key] else { return nil }
        if case .string(let s) = json, !s.isEmpty { return s }
        return nil
    }

    // MARK: - Auth

    private func observeAuthState() async {
        for await (event, session) in auth.authStateChanges {
            switch event {
            case .initialSession:
                authState = session != nil ? .authenticated : .unauthenticated
                if session != nil { await fetchUser() }
            case .signedIn:
                authState = .authenticated
                await fetchUser()
            case .signedOut, .userDeleted:
                authState = .unauthenticated
                currentUser = nil
            default:
                break
            }
        }
    }

    func fetchUser() async {
        currentUser = try? await auth.user()
    }

    func signIn(email: String, password: String) async {
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            try await auth.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        do { try await auth.signOut() }
        catch { errorMessage = error.localizedDescription }
    }

    // MARK: - Profile updates

    func updateName(_ name: String) async throws {
        isUpdating = true; defer { isUpdating = false }
        currentUser = try await auth.update(user: UserAttributes(data: ["full_name": .string(name)]))
    }

    func updateEmail(_ email: String) async throws {
        isUpdating = true; defer { isUpdating = false }
        try await auth.update(user: UserAttributes(email: email))
    }

    func updatePhone(_ phone: String) async throws {
        isUpdating = true; defer { isUpdating = false }
        currentUser = try await auth.update(user: UserAttributes(phone: phone))
    }

    func updatePassword(currentPassword: String, newPassword: String) async throws {
        isUpdating = true; defer { isUpdating = false }
        try await auth.signIn(email: userEmail, password: currentPassword)
        try await auth.update(user: UserAttributes(password: newPassword))
    }

    // MARK: - Avatar

    func uploadAvatar(_ imageData: Data) async throws {
        isUpdating = true; defer { isUpdating = false }
        let userId = try await auth.session.user.id.uuidString
        let bucket = AppConfig.supabaseAvatarBucket
        let path = "\(userId)/avatar.jpg"
        try await storage.from(bucket).upload(
            path,
            data: imageData,
            options: FileOptions(contentType: "image/jpeg", upsert: true)
        )
        let url = try storage.from(bucket).getPublicURL(path: path)
        // Bust cache with timestamp
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "t", value: "\(Int(Date().timeIntervalSince1970))")]
        let finalURL = components?.url ?? url
        currentUser = try await auth.update(user: UserAttributes(data: ["avatar_url": .string(finalURL.absoluteString)]))
    }

    func deleteAvatar() async throws {
        isUpdating = true; defer { isUpdating = false }
        let userId = try await auth.session.user.id.uuidString
        let bucket = AppConfig.supabaseAvatarBucket
        do {
            _ = try await storage.from(bucket).remove(paths: ["\(userId)/avatar.jpg"])
        } catch {
            // Keep going so the avatar disappears from the app even if storage cleanup fails.
            print("[AuthViewModel] avatar delete storage cleanup failed: \(error)")
        }
        currentUser = try await auth.update(user: UserAttributes(data: ["avatar_url": .null]))
    }
}
