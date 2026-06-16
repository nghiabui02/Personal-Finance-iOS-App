import SwiftUI
import SwiftData

struct AddEditRecurringView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let recurring: LocalRecurringTransaction?

    @Query(sort: \LocalCategory.name) private var allCategories: [LocalCategory]
    @Query(sort: \LocalWallet.name) private var wallets: [LocalWallet]

    @State private var type = "expense"
    @State private var amount: Double = 0
    @State private var frequency = "monthly"
    @State private var startDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var selectedCategoryId: UUID?
    @State private var selectedWalletId: UUID?
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorMsg: String?

    private var isEditing: Bool { recurring != nil }
    private var filteredCategories: [LocalCategory] { allCategories.filter { $0.type == type } }

    let frequencies = ["daily", "weekly", "monthly", "yearly"]

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
                        .onChange(of: type) { _, _ in selectedCategoryId = nil }
                    }
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0", value: $amount, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).fontWeight(.semibold)
                        Text("₫").foregroundColor(.secondary)
                    }
                    Picker("Frequency", selection: $frequency) {
                        ForEach(frequencies, id: \.self) { f in
                            Text(f.capitalized).tag(f)
                        }
                    }
                }

                Section {
                    if !isEditing {
                        DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    }
                    Toggle("End Date", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("", selection: $endDate, displayedComponents: .date).datePickerStyle(.compact)
                    }
                }

                Section {
                    Picker("Category", selection: $selectedCategoryId) {
                        Text("None").tag(UUID?.none)
                        ForEach(filteredCategories, id: \.serverId) { cat in
                            HStack { Text(cat.icon ?? "📦"); Text(cat.name) }.tag(Optional(cat.serverId))
                        }
                    }
                    Picker("Wallet", selection: $selectedWalletId) {
                        Text("None").tag(UUID?.none)
                        ForEach(wallets, id: \.serverId) { w in Text(w.name).tag(Optional(w.serverId)) }
                    }
                }

                Section {
                    TextField("Note (optional)", text: $note, axis: .vertical).lineLimit(2...4)
                }
            }
            .navigationTitle(isEditing ? "Edit Recurring" : "New Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView().scaleEffect(0.8) }
                    else {
                        Button("Save") { Task { await save() } }
                            .disabled(amount <= 0)
                    }
                }
            }
            .alert("Error", isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })) {
                Button("OK") { errorMsg = nil }
            } message: { Text(errorMsg ?? "") }
        }
        .onAppear {
            if let r = recurring {
                type = r.type; amount = r.amount; frequency = r.frequency
                selectedCategoryId = r.categoryId; selectedWalletId = r.walletId
                note = r.note ?? ""
                if let ed = r.endDate { hasEndDate = true; endDate = ed }
            } else {
                selectedWalletId = wallets.first(where: { $0.isDefault })?.serverId ?? wallets.first?.serverId
            }
        }
    }

    private func save() async {
        guard amount > 0 else { return }
        isSaving = true; defer { isSaving = false }
        do {
            if let r = recurring {
                try await RecurringService.shared.update(
                    r, amount: amount, frequency: frequency,
                    endDate: hasEndDate ? endDate : nil,
                    walletId: selectedWalletId, categoryId: selectedCategoryId,
                    note: note.isEmpty ? nil : note, in: modelContext
                )
            } else {
                try await RecurringService.shared.create(
                    type: type, amount: amount, frequency: frequency,
                    startDate: startDate, endDate: hasEndDate ? endDate : nil,
                    walletId: selectedWalletId, categoryId: selectedCategoryId,
                    note: note.isEmpty ? nil : note, in: modelContext
                )
            }
            dismiss()
        } catch { errorMsg = error.localizedDescription }
    }
}
