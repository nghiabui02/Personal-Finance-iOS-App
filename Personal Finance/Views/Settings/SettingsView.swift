import SwiftUI
import PhotosUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var authVM: AuthViewModel
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
                // Profile header
                Section {
                    HStack(spacing: 16) {
                        AvatarView(url: authVM.avatarURL, size: 64)
                            .overlay(alignment: .bottomTrailing) {
                                PhotosPicker(selection: $photoItem, matching: .images) {
                                    Image(systemName: "camera.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(.white, Color.blue)
                                        .background(Circle().fill(Color(.systemBackground)).padding(2))
                                }
                                .buttonStyle(.plain)
                            }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(authVM.displayName)
                                .font(.headline)
                            Text(authVM.userEmail)
                                .font(.subheadline).foregroundColor(.secondary)
                        }

                        Spacer()

                        if authVM.isUpdating {
                            ProgressView().scaleEffect(0.8)
                        }
                    }
                    .padding(.vertical, 6)
                }

                // Account
                Section("Account") {
                    settingRow(icon: "person.fill", color: .blue, title: "Name",
                               value: authVM.displayName) {
                        showEditName = true
                    }
                    settingRow(icon: "envelope.fill", color: .orange, title: "Email",
                               value: authVM.userEmail) {
                        showEditEmail = true
                    }
                    settingRow(icon: "phone.fill", color: .green, title: "Phone",
                               value: authVM.userPhone.isEmpty ? "Not set" : authVM.userPhone) {
                        showEditPhone = true
                    }
                    settingRow(icon: "lock.fill", color: .purple, title: "Password",
                               value: "••••••••") {
                        showChangePassword = true
                    }
                }

                // Avatar
                Section("Avatar") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Change Avatar", systemImage: "photo.fill")
                    }
                    .foregroundColor(.primary)

                    if authVM.avatarURL != nil {
                        Button(role: .destructive) {
                            pendingDeletion = .avatar
                            showDeleteConfirmation = true
                        } label: {
                            Label("Remove Avatar", systemImage: "trash")
                        }
                    }
                }

                // Appearance
                Section("Appearance") {
                    Picker(selection: $colorScheme) {
                        Label("System", systemImage: "circle.lefthalf.filled").tag("system")
                        Label("Light", systemImage: "sun.max.fill").tag("light")
                        Label("Dark", systemImage: "moon.fill").tag("dark")
                    } label: {
                        Label("Theme", systemImage: "paintbrush.fill")
                    }
                }

                // Sign Out
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
            .listStyle(.insetGrouped)
            .refreshable { await authVM.fetchUser() }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
        .onChange(of: photoItem) { _, item in
            Task { await handlePhotoPick(item) }
        }
        .sheet(isPresented: $showEditName) {
            EditFieldSheet(
                title: "Name",
                placeholder: "Your name",
                currentValue: authVM.displayName,
                keyboardType: .default
            ) { newValue in
                try await authVM.updateName(newValue)
            }
        }
        .sheet(isPresented: $showEditEmail) {
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
        .sheet(isPresented: $showChangePassword) {
            ChangePasswordSheet()
                .environmentObject(authVM)
        }
        .sheet(isPresented: $showEditPhone) {
            EditFieldSheet(
                title: "Phone",
                placeholder: "+84 ...",
                currentValue: authVM.userPhone,
                keyboardType: .phonePad
            ) { newValue in
                try await authVM.updatePhone(newValue)
            }
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
            Task {
                do { try await authVM.deleteAvatar() }
                catch { errorMsg = error.localizedDescription }
            }
        }
        .errorAlert($errorMsg)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func settingRow(icon: String, color: Color, title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(color)
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text(title).foregroundColor(.primary)
                Spacer()
                Text(value)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func handlePhotoPick(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        defer { photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMsg = "Could not load the selected image."
                return
            }
            guard let uiImage = UIImage(data: data),
                  let compressed = uiImage.jpegData(compressionQuality: 0.75) else {
                errorMsg = "Could not process the image."
                return
            }
            try await authVM.uploadAvatar(compressed)
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}

private enum SettingsDeletion {
    case avatar
}

// MARK: - Avatar View (reusable)

struct AvatarView: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
                .id(url.absoluteString)
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .foregroundStyle(Color(.systemGray3))
    }
}

// MARK: - Edit Field Sheet

enum TextFieldKeyboardType {
    case `default`
    case email
    case phonePad
    
    var swiftUIKeyboardType: UIKeyboardType {
        switch self {
        case .default: return .default
        case .email: return .emailAddress
        case .phonePad: return .phonePad
        }
    }
}

// MARK: - Change Password Sheet

struct ChangePasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authVM: AuthViewModel

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSaving = false
    @State private var errorMsg: String?

    private var passwordsMatch: Bool { newPassword == confirmPassword }
    private var isValid: Bool {
        !currentPassword.isEmpty && newPassword.count >= 6 && passwordsMatch
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Current Password") {
                    SecureField("Enter current password", text: $currentPassword)
                }
                Section("New Password") {
                    SecureField("New password (min. 6 characters)", text: $newPassword)
                    SecureField("Confirm new password", text: $confirmPassword)
                }
                if !confirmPassword.isEmpty && !passwordsMatch {
                    Section {
                        Text("Passwords do not match")
                            .font(.caption).foregroundColor(.red)
                    }
                }
            }
            .formKeyboardHandling()
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView().scaleEffect(0.8) }
                    else {
                        Button("Save") { Task { await save() } }
                            .disabled(!isValid)
                    }
                }
            }
            .errorAlert($errorMsg)
        }
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        do {
            try await authVM.updatePassword(currentPassword: currentPassword, newPassword: newPassword)
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}

// MARK: - Edit Field Sheet

struct EditFieldSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let placeholder: String
    let currentValue: String
    let keyboardType: TextFieldKeyboardType
    var note: String? = nil
    let onSave: (String) async throws -> Void

    @State private var value = ""
    @State private var isSaving = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(placeholder, text: $value)
                        .keyboardType(keyboardType.swiftUIKeyboardType)
                        .textInputAutocapitalization(keyboardType == .email ? .never : .words)
                        .autocorrectionDisabled(keyboardType == .email)
                }
                if let note {
                    Section {
                        Text(note)
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .formKeyboardHandling()
            .navigationTitle("Edit \(title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView().scaleEffect(0.8) }
                    else {
                        Button("Save") { Task { await save() } }
                            .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty || value == currentValue)
                    }
                }
            }
            .errorAlert($errorMsg)
        }
        .onAppear { value = currentValue }
    }

    private func save() async {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true; defer { isSaving = false }
        do {
            try await onSave(trimmed)
            dismiss()
        } catch { errorMsg = error.localizedDescription }
    }
}
