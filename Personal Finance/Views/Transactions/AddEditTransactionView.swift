import SwiftUI
import SwiftData

struct AddEditTransactionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let transaction: LocalTransaction?
    var defaultDate: Date? = nil

    @Query(sort: \LocalCategory.name) private var allCategories: [LocalCategory]
    @Query(sort: \LocalWallet.name) private var wallets: [LocalWallet]
    @Query private var allDebts: [LocalDebt]
    @Query(sort: \LocalTransaction.transactionDate, order: .reverse) private var allTx: [LocalTransaction]

    @State private var type = "expense"
    @State private var amount: Double = 0
    @State private var amountText = ""
    @State private var date = Date()
    @State private var selectedCategoryId: UUID?
    @State private var selectedWalletId: UUID?
    @State private var note = ""

    @State private var showCategoryPicker = false
    @State private var showWalletPicker = false
    @State private var isSaving = false
    @State private var errorMsg: String?

    @State private var hasBankFee = false
    @State private var bankFee: Double = 0
    @State private var bankFeeText = ""
    @State private var linkedDebtId: UUID? = nil
    @State private var showDebtPicker = false
    @State private var frequentSuggestions: [FrequentTransactionSuggestion] = []

    private var isEditing: Bool { transaction != nil }

    // Chips only help on a blank form — once the user has started filling it
    // in, they just take up space.
    private var showFrequentChips: Bool {
        !isEditing && amount == 0 && selectedCategoryId == nil && !frequentSuggestions.isEmpty
    }

    private var filteredCategories: [LocalCategory] {
        allCategories.filter { $0.type == type }
    }

    private var selectedCategory: LocalCategory? {
        allCategories.first { $0.serverId == selectedCategoryId }
    }

    private var selectedWallet: LocalWallet? {
        wallets.first { $0.serverId == selectedWalletId }
    }

    private var isDebtCategory: Bool {
        guard let cat = selectedCategory else { return false }
        return (cat.name == "Thu nợ" && cat.type == "income") ||
               (cat.name == "Trả nợ" && cat.type == "expense")
    }

    private var debtTypeFilter: String {
        // "Thu nợ" = collecting from lend debt; "Trả nợ" = repaying borrow debt
        selectedCategory?.name == "Thu nợ" ? "lend" : "borrow"
    }

    private var activeDebtsForCategory: [LocalDebt] {
        allDebts.filter { $0.type == debtTypeFilter && $0.status != "completed" }
    }

    private var linkedDebt: LocalDebt? {
        allDebts.first { $0.serverId == linkedDebtId }
    }

    var body: some View {
        NavigationStack {
            Form {
                if showFrequentChips {
                    Section {
                        FrequentChipsRow(suggestions: frequentSuggestions, onSelect: applySuggestion)
                    }
                    .listRowInsets(EdgeInsets())
                }

                TransactionTypeAmountSection(
                    type: $type,
                    amount: $amount,
                    amountText: $amountText,
                    onTypeChanged: resetCategoryIfNeeded
                )

                TransactionDetailsSection(
                    date: $date,
                    selectedCategory: selectedCategory,
                    selectedWallet: selectedWallet,
                    onSelectCategory: { showCategoryPicker = true },
                    onSelectWallet: { showWalletPicker = true }
                )

                if isDebtCategory && !isEditing {
                    Section("Debt") {
                        Button {
                            showDebtPicker = true
                        } label: {
                            HStack {
                                Text("Link Debt")
                                Spacer()
                                if let debt = linkedDebt {
                                    Text(debt.personName).foregroundStyle(.secondary)
                                } else {
                                    Text("None").foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                if !isEditing {
                    Section {
                        Toggle("Bank Fee", isOn: $hasBankFee)
                        if hasBankFee {
                            CurrencyAmountField(title: "Fee Amount", amount: $bankFee, amountText: $bankFeeText)
                        }
                    }
                }

                Section {
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formKeyboardHandling()
            .navigationTitle(isEditing ? "Edit Transaction" : "New Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(amount <= 0)
                    }
                }
            }
            .sheet(isPresented: $showCategoryPicker) {
                TransactionCategoryPickerSheet(
                    categories: filteredCategories,
                    selected: $selectedCategoryId,
                    isPresented: $showCategoryPicker
                )
            }
            .sheet(isPresented: $showWalletPicker) {
                TransactionWalletPickerSheet(
                    wallets: wallets,
                    selected: $selectedWalletId,
                    isPresented: $showWalletPicker
                )
            }
            .sheet(isPresented: $showDebtPicker) {
                NavigationStack {
                    List(activeDebtsForCategory, id: \.serverId) { debt in
                        Button {
                            linkedDebtId = debt.serverId
                            showDebtPicker = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(debt.personName).fontWeight(.medium)
                                    Text(debt.remainingAmount.formatted(currency: "VND"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if linkedDebtId == debt.serverId {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .navigationTitle("Select Debt")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showDebtPicker = false }
                        }
                    }
                }
            }
            .errorAlert($errorMsg)
        }
        .onAppear { prefill() }
    }

    private func prefill() {
        if let tx = transaction {
            type = tx.type
            amount = tx.amount
            amountText = tx.amount.formattedDecimal()
            date = tx.transactionDate
            selectedCategoryId = tx.categoryId
            selectedWalletId = tx.walletId
            note = tx.note ?? ""
        } else {
            date = defaultDate ?? Date()
            selectedWalletId = wallets.first(where: { $0.isDefault })?.serverId
                ?? wallets.first?.serverId
            frequentSuggestions = FrequentTransactionSuggestionCalculator.calculate(
                transactions: allTx, categories: allCategories
            )
        }
    }

    private func resetCategoryIfNeeded(newType: String) {
        if let selectedCategory, selectedCategory.type != newType {
            selectedCategoryId = nil
        }
    }

    private func applySuggestion(_ suggestion: FrequentTransactionSuggestion) {
        type = suggestion.type
        amount = suggestion.amount
        amountText = suggestion.amount.formattedDecimal()
        selectedCategoryId = suggestion.categoryId
        if let walletId = suggestion.walletId { selectedWalletId = walletId }
        note = suggestion.note ?? ""
    }

    private func save() async {
        guard amount > 0 else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            if let tx = transaction {
                let oldWallet = wallets.first { $0.serverId == tx.walletId }
                let newWallet = wallets.first { $0.serverId == selectedWalletId }
                try await TransactionService.shared.update(
                    tx, type: type, amount: amount, date: date,
                    walletId: selectedWalletId, categoryId: selectedCategoryId,
                    note: note.isEmpty ? nil : note,
                    oldWallet: oldWallet, newWallet: newWallet,
                    in: modelContext
                )
            } else if isDebtCategory, let debt = linkedDebt {
                try await DebtService.shared.recordPayment(
                    debt, amount: amount,
                    note: note.isEmpty ? nil : note,
                    date: date, wallet: selectedWallet,
                    in: modelContext
                )
            } else {
                let wallet = wallets.first { $0.serverId == selectedWalletId }
                try await TransactionService.shared.create(
                    type: type, amount: amount, date: date,
                    walletId: selectedWalletId, categoryId: selectedCategoryId,
                    note: note.isEmpty ? nil : note,
                    wallet: wallet, bankFee: hasBankFee ? bankFee : 0,
                    in: modelContext
                )
            }
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}

private struct FrequentChipsRow: View {
    let suggestions: [FrequentTransactionSuggestion]
    let onSelect: (FrequentTransactionSuggestion) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions) { suggestion in
                    Button { onSelect(suggestion) } label: {
                        HStack(spacing: 4) {
                            Text(suggestion.categoryIcon)
                            Text(suggestion.amount.formatted(currency: "VND"))
                                .font(.caption).fontWeight(.medium)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }
}
