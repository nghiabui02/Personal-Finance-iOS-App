import SwiftUI
import SwiftData

struct AddEditTransactionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let transaction: LocalTransaction?
    var defaultDate: Date?

    @Query(sort: \LocalCategory.name) private var allCategories: [LocalCategory]
    @Query(sort: \LocalWallet.name) private var wallets: [LocalWallet]
    @Query private var allDebts: [LocalDebt]
    /// Only the window frequent suggestions read from.
    @Query private var recentTx: [LocalTransaction]

    @State private var type = TransactionKind.expense
    @State private var amount: Decimal = 0
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
    @State private var bankFee: Decimal = 0
    @State private var bankFeeText = ""
    @State private var linkedDebtId: UUID?
    @State private var showDebtPicker = false
    private var isEditing: Bool { transaction != nil }

    init(transaction: LocalTransaction?, defaultDate: Date? = nil) {
        self.transaction = transaction
        self.defaultDate = defaultDate
        let start = FrequentTransactionSuggestionCalculator.windowStart()
        _recentTx = Query(filter: #Predicate { $0.transactionDate >= start })
    }

    private var frequentSuggestions: [FrequentTransactionSuggestion] {
        guard !isEditing, amount == 0, selectedCategoryId == nil else { return [] }
        return FrequentTransactionSuggestionCalculator.calculate(transactions: recentTx, categories: allCategories)
    }

    private var filteredCategories: [LocalCategory] {
        allCategories.filter { category in
            guard category.type == type else { return false }
            if category.serverId == transaction?.categoryId { return true }
            guard category.isActiveMembership else { return false }
            guard let key = category.systemKey else { return true }
            return !isEditing && (key == SystemCategory.collectDebt || key == SystemCategory.repayDebt)
        }
    }

    private var selectedCategory: LocalCategory? {
        allCategories.first { $0.serverId == selectedCategoryId }
    }

    private var selectedWallet: LocalWallet? {
        wallets.first { $0.serverId == selectedWalletId }
    }

    private var debtTypeFilter: DebtKind? {
        switch selectedCategory?.systemKey {
        case SystemCategory.collectDebt: .lend
        case SystemCategory.repayDebt: .borrow
        default: nil
        }
    }

    private var activeDebtsForCategory: [LocalDebt] {
        allDebts.filter { $0.type == debtTypeFilter && $0.status == .active && $0.remainingAmount > 0 }
    }

    private var linkedDebt: LocalDebt? {
        activeDebtsForCategory.first { $0.serverId == linkedDebtId }
    }

    private var isDebtPayment: Bool { transaction?.debtPaymentId != nil }
    private var allowsBankFee: Bool {
        type == .expense && selectedWalletId != nil && debtTypeFilter == nil && !isDebtPayment
    }

    var body: some View {
        NavigationStack {
            Form {
                let suggestions = frequentSuggestions
                if !suggestions.isEmpty {
                    Section {
                        FrequentChipsRow(suggestions: suggestions, onSelect: applySuggestion)
                    }
                    .listRowInsets(EdgeInsets())
                }

                TransactionTypeAmountSection(
                    type: $type,
                    amount: $amount,
                    amountText: $amountText,
                    allowsTypeChange: !isDebtPayment,
                    onTypeChanged: resetCategoryIfNeeded
                )

                TransactionDetailsSection(
                    date: $date,
                    selectedCategory: selectedCategory,
                    selectedWallet: selectedWallet,
                    onSelectCategory: { if !isDebtPayment { showCategoryPicker = true } },
                    onSelectWallet: { showWalletPicker = true }
                )

                if debtTypeFilter != nil && !isEditing {
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

                if allowsBankFee {
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
                            .disabled(amount <= 0 || (!isEditing && debtTypeFilter != nil && linkedDebt == nil))
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
            bankFee = tx.bankFee ?? 0
            hasBankFee = bankFee > 0
            bankFeeText = hasBankFee ? bankFee.formattedDecimal() : ""
            amount = tx.amount - bankFee
            amountText = amount.formattedDecimal()
            date = tx.transactionDate
            selectedCategoryId = tx.categoryId
            selectedWalletId = tx.walletId
            note = tx.note ?? ""
        } else {
            date = defaultDate ?? Date()
            selectedWalletId = wallets.first(where: { $0.isDefault })?.serverId
                ?? wallets.first?.serverId
        }
    }

    private func resetCategoryIfNeeded(newType: TransactionKind) {
        if let selectedCategory, selectedCategory.type != newType {
            selectedCategoryId = nil
        }
    }

    private func applySuggestion(_ suggestion: FrequentTransactionSuggestion) {
        type = suggestion.type
        bankFee = suggestion.bankFee
        hasBankFee = bankFee > 0
        bankFeeText = bankFee.formattedDecimal()
        amount = suggestion.amount - bankFee
        amountText = amount.formattedDecimal()
        selectedCategoryId = suggestion.categoryId
        if let walletId = suggestion.walletId { selectedWalletId = walletId }
        note = suggestion.note ?? ""
    }

    private func feeForUpdate(_ transaction: LocalTransaction) -> Decimal {
        if allowsBankFee { return hasBankFee ? bankFee : 0 }
        // Preserve fees on legacy rows when their original wallet and type remain unchanged.
        if !isDebtPayment && transaction.type == type && transaction.walletId == selectedWalletId {
            return transaction.bankFee ?? 0
        }
        return 0
    }

    private func save() async {
        guard amount.isFinite, amount > 0, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            if let tx = transaction {
                try await TransactionService.shared.update(
                    tx, type: type, amount: amount, date: date,
                    walletId: selectedWalletId, categoryId: selectedCategoryId,
                    note: note.isEmpty ? nil : note,
                    bankFee: feeForUpdate(tx),
                    in: modelContext
                )
            } else if debtTypeFilter != nil {
                guard let debt = linkedDebt else {
                    throw BusinessRuleError(message: "Select a debt for this category.")
                }
                try await DebtService.shared.recordPayment(
                    debt, amount: amount,
                    note: note.isEmpty ? nil : note,
                    date: date, walletId: selectedWalletId,
                    categoryId: selectedCategoryId,
                    in: modelContext
                )
            } else {
                try await TransactionService.shared.create(
                    type: type, amount: amount, date: date,
                    walletId: selectedWalletId, categoryId: selectedCategoryId,
                    note: note.isEmpty ? nil : note,
                    bankFee: allowsBankFee && hasBankFee ? bankFee : 0,
                    in: modelContext
                )
            }
            Haptics.moneyRecorded()
            dismiss()
        } catch {
            errorMsg = error.asDisplayableError().localizedDescription
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
                    SuggestionChip(
                        icon: suggestion.categoryIcon,
                        label: suggestion.amount.formatted(currency: "VND")
                    ) {
                        onSelect(suggestion)
                    }
                    .accessibilityLabel(Text("\(suggestion.categoryName), \(suggestion.amount.formatted(currency: "VND"))"))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }
}
