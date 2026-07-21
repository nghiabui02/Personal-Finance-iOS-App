import SwiftUI

struct AppScreenHeaderModifier: ViewModifier {
    @EnvironmentObject private var authViewModel: AuthViewModel
    let title: String

    @StateObject private var notifVM = NotificationViewModel()
    @State private var showsProfile = false

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NotificationBellButton(vm: notifVM)

                    Button {
                        showsProfile = true
                    } label: {
                        AvatarView(url: authViewModel.avatarURL, size: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open profile")
                }
            }
            .sheet(isPresented: $showsProfile) {
                SettingsView(onClose: { showsProfile = false })
                    .environmentObject(authViewModel)
            }
            .onAppear { Task { await notifVM.load() } }
    }
}

extension View {
    func appScreenHeader(_ title: String) -> some View {
        modifier(AppScreenHeaderModifier(title: title))
    }
}
