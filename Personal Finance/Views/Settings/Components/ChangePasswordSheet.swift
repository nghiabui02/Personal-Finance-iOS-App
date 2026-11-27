import SwiftUI

struct ChangePasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authVM: AuthViewModel

    /// Opened from a password-reset link: the user is signed in by the link and has no
    /// current password to confirm.
    var isRecovery = false

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSaving = false
    @State private var errorMsg: String?

    private var passwordsMatch: Bool { newPassword == confirmPassword }
    private var isValid: Bool {
        (isRecovery || !currentPassword.isEmpty) && newPassword.count >= 6 && passwordsMatch
    }

    var body: some View {
        NavigationStack {
            Form {
                if !isRecovery {
                    Section("Current Password") {
                        SecureField("Enter current password", text: $currentPassword)
                            .textContentType(.password)
                    }
                }

                Section("New Password") {
                    SecureField("New password (min. 6 characters)", text: $newPassword)
                        .textContentType(.newPassword)
                    SecureField("Confirm new password", text: $confirmPassword)
                        .textContentType(.newPassword)
                }

                if !confirmPassword.isEmpty && !passwordsMatch {
                    Section {
                        Text("Passwords do not match")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formKeyboardHandling()
            .navigationTitle(isRecovery ? LocalizedStringKey("Set New Password") : "Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                        .disabled(!isValid)
                    }
                }
            }
            .errorAlert($errorMsg)
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        do {
            if isRecovery {
                try await authVM.setRecoveredPassword(newPassword)
            } else {
                try await authVM.updatePassword(
                    currentPassword: currentPassword,
                    newPassword: newPassword
                )
            }
            dismiss()
        } catch {
            errorMsg = error.asDisplayableError().localizedDescription
        }
    }
}
