import SwiftUI

struct AppScreenHeaderModifier: ViewModifier {
    @EnvironmentObject private var authViewModel: AuthViewModel
    let title: LocalizedStringKey

    @EnvironmentObject private var notifVM: NotificationViewModel
    @State private var showsProfile = false

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
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
    }
}

extension View {
    func appScreenHeader(_ title: LocalizedStringKey) -> some View {
        modifier(AppScreenHeaderModifier(title: title))
    }
}
