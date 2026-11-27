import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var isSigningUp = false
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !password.isEmpty
        && (!isSigningUp || password.count >= 6)
        && !authVM.isLoading
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            VStack(spacing: 12) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue.gradient)
                    .accessibilityHidden(true)
                Text("Personal Finance")
                    .font(.largeTitle).fontWeight(.bold)
                Text("Manage your personal finances")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Spacer().frame(height: 48)

            // Form
            VStack(spacing: 16) {
                // `.username` + `.password`/`.newPassword` is what lets iOS offer saved
                // passwords from Keychain and suggest a strong one on sign-up.
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .email)
                    .onSubmit { focusedField = .password }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(.rect(cornerRadius: 12))

                SecureField("Password", text: $password)
                    .textContentType(isSigningUp ? .newPassword : .password)
                    .submitLabel(.go)
                    .focused($focusedField, equals: .password)
                    .onSubmit(submit)
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(.rect(cornerRadius: 12))

                if let error = authVM.errorMessage {
                    Text(error)
                        .font(.caption).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let notice = authVM.authNotice {
                    Text(notice)
                        .font(.caption).foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: submit) {
                    ZStack {
                        if authVM.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text(isSigningUp ? "Create Account" : "Sign In").fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                    .background(canSubmit ? Color.blue : Color.gray)
                    .foregroundStyle(.white)
                    .clipShape(.rect(cornerRadius: 12))
                }
                .disabled(!canSubmit)

                HStack {
                    Button(isSigningUp ? "Already have an account?" : "Create account") {
                        isSigningUp.toggle()
                        authVM.errorMessage = nil
                        authVM.authNotice = nil
                    }
                    Spacer()
                    if !isSigningUp {
                        Button("Forgot password?") {
                            Task { await authVM.sendPasswordReset(email: email) }
                        }
                    }
                }
                .font(.subheadline)
            }
            .padding(.horizontal, 24)

            Spacer()
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { hideKeyboard() }
    }

    private func submit() {
        guard canSubmit else { return }
        focusedField = nil
        Task {
            if isSigningUp {
                await authVM.signUp(email: email, password: password)
            } else {
                await authVM.signIn(email: email, password: password)
            }
        }
    }
}
