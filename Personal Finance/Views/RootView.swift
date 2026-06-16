import SwiftUI

struct RootView: View {
    @StateObject private var authVM = AuthViewModel()
    @AppStorage("pf_colorScheme") private var colorScheme = "system"

    var body: some View {
        Group {
            switch authVM.authState {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
            case .authenticated:
                MainTabView()
                    .environmentObject(authVM)
            case .unauthenticated:
                LoginView()
                    .environmentObject(authVM)
            }
        }
        .preferredColorScheme(
            colorScheme == "light" ? .light :
            colorScheme == "dark" ? .dark : nil
        )
    }
}
