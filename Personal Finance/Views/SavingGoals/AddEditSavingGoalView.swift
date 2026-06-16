import SwiftUI
import SwiftData

struct AddEditSavingGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let goal: LocalSavingGoal?

    @State private var name = ""
    @State private var icon = "🎯"
    @State private var targetAmount: Double = 0
    @State private var targetAmountText = ""
    @State private var hasDeadline = false
    @State private var deadline = Date()
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Icon")
                        Spacer()
                        TextField("Emoji", text: $icon).multilineTextAlignment(.trailing).frame(width: 60)
                    }
                    HStack {
                        Text("Name")
                        TextField("e.g. New Car", text: $name).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Target Amount")
                        Spacer()
                        TextField("0", text: $targetAmountText)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).fontWeight(.semibold)
                            .onChange(of: targetAmountText) { _, new in
                                applyAmountFormat(new: new, amountText: &targetAmountText, amount: &targetAmount)
                            }
                        Text("₫").foregroundColor(.secondary)
                    }
                }
                Section {
                    Toggle("Deadline", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("", selection: $deadline, displayedComponents: .date).datePickerStyle(.compact)
                    }
                    TextField("Note (optional)", text: $note, axis: .vertical).lineLimit(2...4)
                }
            }
            .navigationTitle(goal != nil ? "Edit Goal" : "New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView().scaleEffect(0.8) }
                    else {
                        Button("Save") { Task { await save() } }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || targetAmount <= 0)
                    }
                }
            }
            .alert("Error", isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })) {
                Button("OK") { errorMsg = nil }
            } message: { Text(errorMsg ?? "") }
        }
        .onAppear {
            if let g = goal {
                name = g.name; icon = g.icon ?? "🎯"
                targetAmount = g.targetAmount
                targetAmountText = g.targetAmount.formattedDecimal()
                note = g.note ?? ""
                if let dl = g.deadline { hasDeadline = true; deadline = dl }
            }
        }
    }

    private func save() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, targetAmount > 0 else { return }
        isSaving = true; defer { isSaving = false }
        do {
            if let g = goal {
                try await SavingGoalService.shared.update(
                    g, name: trimmed, icon: icon.isEmpty ? nil : icon,
                    targetAmount: targetAmount, deadline: hasDeadline ? deadline : nil,
                    note: note.isEmpty ? nil : note, in: modelContext
                )
            } else {
                try await SavingGoalService.shared.create(
                    name: trimmed, icon: icon.isEmpty ? nil : icon,
                    targetAmount: targetAmount, deadline: hasDeadline ? deadline : nil,
                    note: note.isEmpty ? nil : note, in: modelContext
                )
            }
            dismiss()
        } catch { errorMsg = error.localizedDescription }
    }
}
