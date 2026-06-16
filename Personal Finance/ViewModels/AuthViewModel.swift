import Foundation
import SwiftUI
import Supabase

enum AuthState {
    case loading, authenticated, unauthenticated
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var authState: AuthState = .loading
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let auth = SupabaseService.shared.client.auth

    init() {
        Task { await observeAuthState() }
    }

    private func observeAuthState() async {
        for await (event, session) in auth.authStateChanges {
            switch event {
            case .initialSession:
                authState = session != nil ? .authenticated : .unauthenticated
            case .signedIn:
                authState = .authenticated
            case .signedOut, .userDeleted:
                authState = .unauthenticated
            default:
                break
            }
        }
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await auth.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        do {
            try await auth.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
