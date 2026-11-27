import SwiftUI
import SwiftData

struct AddEditRecurringView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let recurring: LocalRecurringTransaction?

    @Query(sort: \LocalCategory.name) private var allCategories: [LocalCategory]
    @Query(sort: \LocalWallet.name) private var wallets: [LocalWallet]

    @State private var type = TransactionKind.expense
    @State private var amount: Decimal = 0
    @State private var amountText = ""
    @State private var frequency = RecurringFrequency.monthly
    @State private var startDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var selectedCategoryId: UUID?
    @State private var selectedWalletId: UUID?
    @State private var note = ""
    @State private var bankFee: Decimal = 0
    @State private var bankFeeText = ""
    @State private var hasBankFee = false
    @State private var isSaving = false
    @State private var errorMsg: String?

    private var isEditing: Bool { recurring != nil }
    private var filteredCategories: [LocalCategory] { allCategories.filter { category in
        guard category.type == type else { return false }
        if category.serverId == recurring?.categoryId { return true }
        return category.isActiveMembership && category.systemKey.map { !SystemCategory.debtKeys.contains($0) } != false
    } }


    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !isEditing {
                        Picker("Type", selection: $type) {
                            Text("Expense").tag(TransactionKind.expense)
                            Text("Income").tag(TransactionKind.income)
                        }
                        .pickerStyle(.segmented)
                        .tint(type == .income ? .income : .expense)
                        .onChange(of: type) { _, _ in selectedCategoryId = nil }
                    }
                    CurrencyAmountField(amount: $amount, amountText: $amountText)
                    Picker("Frequency", selection: $frequency) {
                        ForEach(RecurringFrequency.allCases, id: \.self) { f in
                            Text(LocalizedStringKey(f.rawValue.capitalized)).tag(f)
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
                            Text("\(cat.icon ?? "📦") \(cat.displayName)").tag(Optional(cat.serverId))
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

                Section {
                    Toggle("Bank Fee", isOn: $hasBankFee)
                    if hasBankFee {
                        CurrencyAmountField(title: "Fee Amount", amount: $bankFee, amountText: $bankFeeText)
                    }
                }
            }
            .formKeyboardHandling()
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
            .errorAlert($errorMsg)
        }
        .onAppear {
            if let r = recurring {
                type = r.type; frequency = r.frequency
                amount = r.amount; amountText = r.amount.formattedDecimal()
                selectedCategoryId = r.categoryId; selectedWalletId = r.walletId
                note = r.note ?? ""
                if let ed = r.endDate { hasEndDate = true; endDate = ed }
                if r.bankFee > 0 { hasBankFee = true; bankFee = r.bankFee; bankFeeText = r.bankFee.formattedDecimal() }
            } else {
                selectedWalletId = wallets.first(where: { $0.isDefault })?.serverId ?? wallets.first?.serverId
            }
        }
    }

    private func save() async {
        guard amount > 0 else { return }
        isSaving = true; defer { isSaving = false }
        let draft = RecurringRuleDraft(
            type: type, amount: amount, frequency: frequency,
            startDate: startDate, endDate: hasEndDate ? endDate : nil,
            walletId: selectedWalletId, categoryId: selectedCategoryId,
            note: note.isEmpty ? nil : note,
            bankFee: hasBankFee ? bankFee : 0
        )
        do {
            if let r = recurring {
                try await RecurringService.shared.update(r, with: draft, in: modelContext)
            } else {
                try await RecurringService.shared.create(draft, in: modelContext)
            }
            dismiss()
        } catch { errorMsg = error.asDisplayableError().localizedDescription }
    }
}
