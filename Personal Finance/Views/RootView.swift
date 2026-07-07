import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var authVM = AuthViewModel()
    @AppStorage("pf_colorScheme") private var colorScheme = "system"

    var body: some View {
        Group {
            switch authVM.authState {
            case .loading:
                loadingView
            case .authenticated:
                if authVM.currentUser == nil {
                    loadingView
                } else {
                    MainTabView()
                        .environmentObject(authVM)
                }
            case .unauthenticated:
                LoginView()
                    .environmentObject(authVM)
            }
        }
        .preferredColorScheme(
            colorScheme == "light" ? .light :
            colorScheme == "dark" ? .dark : nil
        )
        .onChange(of: authVM.currentUser?.id) { _, userId in
            guard let userId else { return }
            LocalDataStore.prepareForAuthenticatedUser(userId, in: modelContext)
        }
        .onChange(of: authVM.authState) { _, state in
            if case .unauthenticated = state {
                LocalDataStore.clearForSignedOutUser(in: modelContext)
            }
        }
    }

    private var loadingView: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
    }
}
