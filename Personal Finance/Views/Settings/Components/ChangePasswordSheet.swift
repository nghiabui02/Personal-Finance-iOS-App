import SwiftUI

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
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .formKeyboardHandling()
            .navigationTitle("Change Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await authVM.updatePassword(
                currentPassword: currentPassword,
                newPassword: newPassword
            )
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}
