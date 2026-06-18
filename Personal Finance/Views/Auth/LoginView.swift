import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @State private var email = ""
    @State private var password = ""

    private var canSubmit: Bool { !email.isEmpty && !password.isEmpty && !authVM.isLoading }

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

                Button {
                    Task { await authVM.signIn(email: email, password: password) }
                } label: {
                    ZStack {
                        if authVM.isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Sign In").fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(canSubmit ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(!canSubmit)
            }
            .padding(.horizontal, 24)

            Spacer()
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { hideKeyboard() }
    }
}
