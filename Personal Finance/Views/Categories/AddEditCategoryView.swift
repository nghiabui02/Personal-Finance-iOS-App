import SwiftUI
import SwiftData

struct AddEditCategoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let category: LocalCategory?

    @State private var name = ""
    @State private var type = "expense"
    @State private var icon = "📦"
    @State private var colorHex = "3B82F6"
    @State private var isSaving = false
    @State private var errorMsg: String?

    private var isEditing: Bool { category != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !isEditing {
                        Picker("Type", selection: $type) {
                            Text("Expense").tag("expense")
                            Text("Income").tag("income")
                        }
                        .pickerStyle(.segmented)
                    }
                    HStack {
                        Text("Icon")
                        Spacer()
                        EmojiPickerButton(emoji: $icon)
                    }
                    HStack {
                        Text("Name")
                        TextField("e.g. Food", text: $name)
                    }
                    HStack {
                        Text("Color")
                        Spacer()
                        ColorSwatchPicker(selected: $colorHex)
                    }
                }
            }
            .formKeyboardHandling()
            .navigationTitle(isEditing ? "Edit Category" : "New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView().scaleEffect(0.8) }
                    else {
                        Button("Save") { Task { await save() } }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .alert("Error", isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })) {
                Button("OK") { errorMsg = nil }
            } message: { Text(errorMsg ?? "") }
        }
        .onAppear {
            if let cat = category {
                name = cat.name
                type = cat.type
                icon = cat.icon ?? "📦"
                if let c = cat.color {
                    colorHex = c.hasPrefix("#") ? String(c.dropFirst()).uppercased() : c.uppercased()
                }
            }
        }
    }

    private func save() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true; defer { isSaving = false }
        do {
            let color = "#\(colorHex)"
            if let cat = category {
                try await CategoryService.shared.update(cat, name: trimmed, icon: icon.isEmpty ? nil : icon, color: color, in: modelContext)
            } else {
                try await CategoryService.shared.create(name: trimmed, type: type, icon: icon.isEmpty ? nil : icon, color: color, in: modelContext)
            }
            dismiss()
        } catch { errorMsg = error.localizedDescription }
    }
}
