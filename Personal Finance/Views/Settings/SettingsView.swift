import SwiftUI
import PhotosUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    var onClose: (() -> Void)?
    @AppStorage("pf_colorScheme") private var colorScheme = "system"

    @State private var showEditName = false
    @State private var showEditEmail = false
    @State private var showEditPhone = false
    @State private var showChangePassword = false
    @State private var showSignOutConfirm = false
    @State private var pendingDeletion: SettingsDeletion?
    @State private var showDeleteConfirmation = false
    @State private var photoItem: PhotosPickerItem?
    @State private var errorMsg: String?

    var body: some View {
        NavigationStack {
            List {
                profileSection
                accountSection
                avatarSection
                appearanceSection
                languageSection
                signOutSection
            }
            .listStyle(.insetGrouped)
            .refreshable { await authVM.fetchUser() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", action: onClose)
                    }
                }
            }
        }
        .onChange(of: photoItem) { _, item in
            Task { await handlePhotoPick(item) }
        }
        .sheet(isPresented: $showEditName) { editNameSheet }
        .sheet(isPresented: $showEditEmail) { editEmailSheet }
        .sheet(isPresented: $showEditPhone) { editPhoneSheet }
        .sheet(isPresented: $showChangePassword) {
            ChangePasswordSheet()
                .environmentObject(authVM)
        }
        .confirmationDialog("Sign Out", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { await authVM.signOut() }
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .deleteConfirmation(
            item: $pendingDeletion,
            isPresented: $showDeleteConfirmation,
            title: "Remove Avatar?",
            message: "Your current avatar will be permanently removed."
        ) { deletion in
            guard deletion == .avatar else { return }
            Task { await deleteAvatar() }
        }
        .errorAlert($errorMsg)
    }

    private var profileSection: some View {
        Section {
            SettingsProfileHeader(
                avatarURL: authVM.avatarURL,
                displayName: authVM.displayName,
                email: authVM.userEmail,
                isUpdating: authVM.isUpdating,
                photoItem: $photoItem
            )
        }
    }

    private var accountSection: some View {
        Section("Account") {
            SettingsRow(
                icon: "person.fill",
                color: .blue,
                title: "Name",
                value: authVM.displayName
            ) {
                showEditName = true
            }

            SettingsRow(
                icon: "envelope.fill",
                color: .orange,
                title: "Email",
                value: authVM.userEmail
            ) {
                showEditEmail = true
            }

            SettingsRow(
                icon: "phone.fill",
                color: .green,
                title: "Phone",
                value: authVM.userPhone.isEmpty ? AppLocalization.shared.language.text("Not set") : authVM.userPhone
            ) {
                showEditPhone = true
            }

            SettingsRow(
                icon: "lock.fill",
                color: .purple,
                title: "Password",
                value: "••••••••"
            ) {
                showChangePassword = true
            }
        }
    }

    private var avatarSection: some View {
        Section("Avatar") {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Change Avatar", systemImage: "photo.fill")
            }
            .foregroundStyle(.primary)

            if authVM.avatarURL != nil {
                Button(role: .destructive) {
                    pendingDeletion = .avatar
                    showDeleteConfirmation = true
                } label: {
                    Label("Remove Avatar", systemImage: "trash")
                }
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker(selection: $colorScheme) {
                Label("System", systemImage: "circle.lefthalf.filled").tag("system")
                Label("Light", systemImage: "sun.max.fill").tag("light")
                Label("Dark", systemImage: "moon.fill").tag("dark")
            } label: {
                Label("Theme", systemImage: "paintbrush.fill")
            }
        }
    }

    private var languageSection: some View {
        Section {
            Picker("Language", selection: Binding(
                get: { AppLocalization.shared.language },
                set: { language in Task { await saveLanguage(language) } }
            )) {
                ForEach(AppLanguage.allCases) { language in
                    Text(verbatim: language.autonym).tag(language)
                }
            }
            .disabled(authVM.isUpdating)
        }
    }

    private func saveLanguage(_ language: AppLanguage) async {
        do {
            try await authVM.updateLanguage(language)
        } catch is CancellationError {
            return
        } catch {
            errorMsg = error.asDisplayableError().localizedDescription
        }
    }

    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                HStack {
                    Spacer()
                    Text("Sign Out")
                    Spacer()
                }
            }
        }
    }

    private var editNameSheet: some View {
        EditFieldSheet(
            title: "Name",
            placeholder: "Your name",
            currentValue: authVM.displayName,
            keyboardType: .default
        ) { newValue in
            try await authVM.updateName(newValue)
        }
    }

    private var editEmailSheet: some View {
        EditFieldSheet(
            title: "Email",
            placeholder: "your@email.com",
            currentValue: authVM.userEmail,
            keyboardType: .email,
            note: "A confirmation will be sent to the new email."
        ) { newValue in
            try await authVM.updateEmail(newValue)
        }
    }

    private var editPhoneSheet: some View {
        EditFieldSheet(
            title: "Phone",
            placeholder: "+84 ...",
            currentValue: authVM.userPhone,
            keyboardType: .phonePad
        ) { newValue in
            try await authVM.updatePhone(newValue)
        }
    }

    private func handlePhotoPick(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        defer { photoItem = nil }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMsg = AppLocalization.shared.language.text("Could not load the selected image.")
                return
            }
            guard let uiImage = UIImage(data: data),
                  let compressed = Self.avatarSized(uiImage).jpegData(compressionQuality: 0.75) else {
                errorMsg = AppLocalization.shared.language.text("Could not process the image.")
                return
            }
            try await authVM.uploadAvatar(compressed)
        } catch {
            errorMsg = error.asDisplayableError().localizedDescription
        }
    }

    /// Avatars render at a few dozen points; uploading the camera original sent several MB.
    private static let avatarMaxPixelSide: CGFloat = 512

    private static func avatarSized(_ image: UIImage) -> UIImage {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > avatarMaxPixelSide else { return image }
        let scale = avatarMaxPixelSide / longestSide
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func deleteAvatar() async {
        do {
            try await authVM.deleteAvatar()
        } catch {
            errorMsg = error.asDisplayableError().localizedDescription
        }
    }
}

private enum SettingsDeletion {
    case avatar
}
