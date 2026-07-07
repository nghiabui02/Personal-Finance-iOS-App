import SwiftUI

struct EditFieldSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let placeholder: String
    let currentValue: String
    let keyboardType: TextFieldKeyboardType
    var note: String?
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
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .formKeyboardHandling()
            .navigationTitle("Edit \(title)")
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
                        .disabled(!canSave)
                    }
                }
            }
            .errorAlert($errorMsg)
        }
        .onAppear { value = currentValue }
    }

    private var canSave: Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed != currentValue
    }

    private func save() async {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await onSave(trimmed)
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}
