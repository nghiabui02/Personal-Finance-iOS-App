import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var authVM = AuthViewModel()
    @AppStorage("pf_colorScheme") private var colorScheme = "system"
    @Environment(\.scenePhase) private var scenePhase
    @State private var preparedUser: UUID?
    @State private var cacheError: String?

    private enum CacheIdentity: Equatable {
        case waiting, signedOut, signedIn(UUID)
    }

    private var cacheIdentity: CacheIdentity {
        switch authVM.authState {
        case .loading: .waiting
        case .unauthenticated: .signedOut
        case .authenticated: authVM.currentUser.map { .signedIn($0.id) } ?? .waiting
        }
    }

    var body: some View {
        Group {
            switch authVM.authState {
            case .loading:
                loadingView
            case .authenticated:
                if let cacheError {
                    ContentUnavailableView("Unable to load saved data", systemImage: "exclamationmark.triangle",
                                           description: Text(cacheError))
                } else if let preparedUser, cacheIdentity == .signedIn(preparedUser) {
                    MainTabView()
                        .id(preparedUser)
                        .environment(\.timeZone, LedgerDate.timeZone)
                        .environment(\.calendar, LedgerDate.calendar)
                        .environmentObject(authVM)
                } else {
                    loadingView
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
        .onChange(of: cacheIdentity, initial: true) { _, identity in
            switch identity {
            case .waiting: break
            case .signedOut: prepareCache(for: nil)
            case .signedIn(let userId): prepareCache(for: userId)
            }
        }
        .overlay {
            if scenePhase != .active {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
    }

    private func prepareCache(for userId: UUID?) {
        preparedUser = nil
        cacheError = nil
        do {
            try LocalDataStore.prepare(for: userId, in: modelContext)
            preparedUser = userId
        } catch {
            cacheError = error.localizedDescription
        }
    }

    private var loadingView: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
    }
}
