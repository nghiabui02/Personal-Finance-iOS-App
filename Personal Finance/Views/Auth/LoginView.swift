import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var isSigningUp = false

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
                Text("Personal Finance")
                    .font(.largeTitle).fontWeight(.bold)
                Text("Manage your personal finances")
                    .font(.subheadline).foregroundColor(.secondary)
            }

            Spacer().frame(height: 48)

            // Form
            VStack(spacing: 16) {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                SecureField("Password", text: $password)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                if let error = authVM.errorMessage {
                    Text(error)
                        .font(.caption).foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let notice = authVM.authNotice {
                    Text(notice)
                        .font(.caption).foregroundColor(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task {
                        if isSigningUp {
                            await authVM.signUp(email: email, password: password)
                        } else {
                            await authVM.signIn(email: email, password: password)
                        }
                    }
                } label: {
                    ZStack {
                        if authVM.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text(isSigningUp ? "Create Account" : "Sign In").fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(canSubmit ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
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
}
