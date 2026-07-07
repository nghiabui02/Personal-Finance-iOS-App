import SwiftUI
import SwiftData

struct AddEditTransactionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let transaction: LocalTransaction?
    var defaultDate: Date? = nil

    @Query(sort: \LocalCategory.name) private var allCategories: [LocalCategory]
    @Query(sort: \LocalWallet.name) private var wallets: [LocalWallet]

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

    private var isEditing: Bool { transaction != nil }

    private var filteredCategories: [LocalCategory] {
        allCategories.filter { $0.type == type }
    }

    private var selectedCategory: LocalCategory? {
        allCategories.first { $0.serverId == selectedCategoryId }
    }

    private var selectedWallet: LocalWallet? {
        wallets.first { $0.serverId == selectedWalletId }
    }

    var body: some View {
        NavigationStack {
            Form {
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
        }
    }

    private func resetCategoryIfNeeded(newType: String) {
        if let selectedCategory, selectedCategory.type != newType {
            selectedCategoryId = nil
        }
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
            } else {
                let wallet = wallets.first { $0.serverId == selectedWalletId }
                try await TransactionService.shared.create(
                    type: type, amount: amount, date: date,
                    walletId: selectedWalletId, categoryId: selectedCategoryId,
                    note: note.isEmpty ? nil : note,
                    wallet: wallet,
                    in: modelContext
                )
            }
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}
