import Foundation
import SwiftUI
import Supabase

enum AuthState: Equatable {
    case loading, authenticated, unauthenticated
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var authState: AuthState = .loading
    @Published var currentUser: User? {
        didSet {
            let language = metaString("locale").flatMap(AppLanguage.init(rawValue:))
            AppLocalization.shared.language = currentUser == nil ? .deviceLanguage : language ?? .vietnamese
        }
    }
    @Published var isLoading = false
    @Published var isUpdating = false
    @Published var errorMessage: String?
    @Published var updateError: String?
    @Published var authNotice: String?
    /// Set once a password-reset link has signed the user in, so the app asks for a new password.
    @Published var isRecoveringPassword = false

    private let auth = SupabaseService.shared.client.auth
    private let storage = SupabaseService.shared.client.storage

    init() {
        Task { await observeAuthState() }
    }

    // MARK: - Computed profile info

    var displayName: String {
        metaString("full_name") ?? currentUser?.email?.components(separatedBy: "@").first ?? AppLocalization.shared.language.text("User")
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
            case .initialSession, .signedIn:
                currentUser = session?.user
                authState = session != nil ? .authenticated : .unauthenticated
                if session != nil { Task { await fetchUser() } }
            case .userUpdated, .tokenRefreshed:
                if let user = session?.user, user.id == currentUser?.id { currentUser = user }
            case .signedOut, .userDeleted:
                authState = .unauthenticated
                currentUser = nil
                isRecoveringPassword = false
            default:
                break
            }
        }
    }

    func fetchUser() async {
        let previousLocale = metaString("locale")
        guard !isUpdating, let user = try? await auth.user(), auth.currentSession?.user.id == user.id,
              !isUpdating, metaString("locale") == previousLocale else { return }
        currentUser = user
    }

    func signIn(email: String, password: String) async {
        isLoading = true; errorMessage = nil; authNotice = nil
        defer { isLoading = false }
        do {
            try await auth.signIn(email: email, password: password)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func signUp(email: String, password: String) async {
        guard password.count >= 6 else {
            errorMessage = AppLocalization.shared.language.text("Password must contain at least 6 characters.")
            return
        }
        isLoading = true; errorMessage = nil; authNotice = nil
        defer { isLoading = false }
        do {
            let response = try await auth.signUp(email: email, password: password)
            if response.session == nil {
                authNotice = AppLocalization.shared.language.text("Check your email to confirm your account.")
            }
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func sendPasswordReset(email: String) async {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = AppLocalization.shared.language.text("Enter your email address first.")
            return
        }
        isLoading = true; errorMessage = nil; authNotice = nil
        defer { isLoading = false }
        let sentNotice = AppLocalization.shared.language.text(
            "If an account exists, password reset instructions have been sent.")
        do {
            try await auth.resetPasswordForEmail(email, redirectTo: AppConfig.passwordResetRedirectURL)
            authNotice = sentNotice
        } catch let error where error.isOfflineError {
            errorMessage = AppLocalization.shared.language.text(
                "No internet connection. Check your connection and try again.")
        } catch {
            // Any other failure reads like success, so the reply never reveals whether the address is registered.
            authNotice = sentNotice
        }
    }

    /// The reset email links back to `AppConfig.passwordResetRedirectURL`. Exchanging the
    /// code in it signs the user in; `isRecoveringPassword` then opens the new-password sheet.
    /// The exchange needs the PKCE verifier saved when the reset was requested, so a link
    /// opened on another device, or after a newer request, fails here.
    func handlePasswordResetLink(_ url: URL) async {
        let redirect = AppConfig.passwordResetRedirectURL
        guard url.scheme == redirect.scheme, url.host() == redirect.host() else { return }
        errorMessage = nil; authNotice = nil
        do {
            try await auth.session(from: url)
            isRecoveringPassword = true
        } catch {
            errorMessage = AppLocalization.shared.language.text(
                "This reset link has expired or was opened on another device. Request a new one.")
        }
    }

    func setRecoveredPassword(_ newPassword: String) async throws {
        isUpdating = true; defer { isUpdating = false }
        currentUser = try await auth.update(user: UserAttributes(password: newPassword))
        isRecoveringPassword = false
    }

    func signOut() async {
        do { try await auth.signOut() }
        catch { errorMessage = error.localizedDescription }
    }

    /// Supabase words its auth errors in English for developers; these are the ones a
    /// person signing in actually hits, phrased for them and localized.
    private static func message(for error: Error) -> String {
        let language = AppLocalization.shared.language
        guard let authError = error as? AuthError else { return error.asDisplayableError().localizedDescription }
        switch authError.errorCode {
        case .invalidCredentials:
            return language.text("Incorrect email or password.")
        case .emailNotConfirmed:
            return language.text("Confirm your email address before signing in.")
        case .userAlreadyExists, .emailExists:
            return language.text("An account with this email already exists.")
        case .weakPassword:
            return language.text("Choose a stronger password.")
        case .overRequestRateLimit, .overEmailSendRateLimit:
            return language.text("Too many attempts. Try again in a few minutes.")
        default:
            return authError.localizedDescription
        }
    }

    // MARK: - Profile updates

    func updateLanguage(_ language: AppLanguage) async throws {
        guard let session = LocalDataStore.session, currentUser?.id == session.userId, !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        let user = try await auth.update(user: UserAttributes(data: ["locale": .string(language.rawValue)]))
        try LocalDataStore.validate(session)
        currentUser = user
    }

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
        let userId = try await auth.session.user.id.uuidString.lowercased()
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
        let userId = try await auth.session.user.id.uuidString.lowercased()
        let bucket = AppConfig.supabaseAvatarBucket
        do {
            _ = try await storage.from(bucket).remove(paths: ["\(userId)/avatar.jpg"])
        } catch {
            // Keep going so the avatar disappears from the app even if storage cleanup fails.
            #if DEBUG
            print("[AuthViewModel] avatar delete storage cleanup failed: \(error)")
            #endif
        }
        currentUser = try await auth.update(user: UserAttributes(data: ["avatar_url": .null]))
    }
}
