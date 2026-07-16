import SwiftUI

struct AppScreenHeaderModifier: ViewModifier {
    @EnvironmentObject private var authViewModel: AuthViewModel
    let title: String

    @State private var showsNotifications = false
    @State private var showsProfile = false

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showsNotifications = true
                    } label: {
                        Image(systemName: "bell")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Notifications")

                    Button {
                        showsProfile = true
                    } label: {
                        AvatarView(url: authViewModel.avatarURL, size: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open profile")
                }
            }
            .sheet(isPresented: $showsNotifications) {
                NavigationStack {
                    ContentUnavailableView(
                        "No Notifications",
                        systemImage: "bell.slash",
                        description: Text("New notifications will appear here")
                    )
                    .navigationTitle("Notifications")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsNotifications = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showsProfile) {
                SettingsView(onClose: { showsProfile = false })
                    .environmentObject(authViewModel)
            }
    }
}

extension View {
    func appScreenHeader(_ title: String) -> some View {
        modifier(AppScreenHeaderModifier(title: title))
    }
}
