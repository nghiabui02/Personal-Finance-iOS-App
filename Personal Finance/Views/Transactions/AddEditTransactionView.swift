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
                // Type toggle + Amount
                Section {
                    Picker("Type", selection: $type) {
                        Text("Expense").tag("expense")
                        Text("Income").tag("income")
                    }
                    .pickerStyle(.segmented)
                    .tint(type == "income" ? .income : .expense)
                    .onChange(of: type) { _, newType in
                        if let cat = selectedCategory, cat.type != newType {
                            selectedCategoryId = nil
                        }
                    }

                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0", text: $amountText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .fontWeight(.semibold)
                            .onChange(of: amountText) { _, new in
                                applyAmountFormat(new: new, amountText: &amountText, amount: &amount)
                            }
                        Text("₫").foregroundColor(.secondary)
                    }
                }

                // Details
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    // Category row
                    Button { showCategoryPicker = true } label: {
                        HStack {
                            Text("Category").foregroundColor(.primary)
                            Spacer()
                            if let cat = selectedCategory {
                                HStack(spacing: 4) {
                                    Text(cat.icon ?? "📦")
                                    Text(cat.name).foregroundColor(.secondary)
                                }
                            } else {
                                Text("Select").foregroundColor(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }

                    // Wallet row
                    Button { showWalletPicker = true } label: {
                        HStack {
                            Text("Wallet").foregroundColor(.primary)
                            Spacer()
                            if let w = selectedWallet {
                                Text(w.name).foregroundColor(.secondary)
                            } else {
                                Text("Select").foregroundColor(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundColor(.secondary)
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
                CategoryPickerSheet(
                    categories: filteredCategories,
                    selected: $selectedCategoryId,
                    isPresented: $showCategoryPicker
                )
            }
            .sheet(isPresented: $showWalletPicker) {
                WalletPickerSheet(
                    wallets: wallets,
                    selected: $selectedWalletId,
                    isPresented: $showWalletPicker
                )
            }
            .alert("Error", isPresented: Binding(
                get: { errorMsg != nil },
                set: { if !$0 { errorMsg = nil } }
            )) {
                Button("OK") { errorMsg = nil }
            } message: {
                Text(errorMsg ?? "")
            }
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

// MARK: - Category Picker Sheet

private struct CategoryPickerSheet: View {
    let categories: [LocalCategory]
    @Binding var selected: UUID?
    @Binding var isPresented: Bool
    @State private var search = ""

    private var displayed: [LocalCategory] {
        search.isEmpty ? categories
            : categories.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if displayed.isEmpty {
                    ContentUnavailableView("No Categories", systemImage: "tag")
                } else {
                    List(displayed, id: \.serverId) { cat in
                        Button {
                            selected = cat.serverId
                            isPresented = false
                        } label: {
                            HStack(spacing: 12) {
                                Text(cat.icon ?? "📦").font(.title3)
                                Text(cat.name).foregroundColor(.primary)
                                Spacer()
                                if selected == cat.serverId {
                                    Image(systemName: "checkmark").foregroundColor(.blue)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .searchable(text: $search, prompt: "Search")
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }
}

// MARK: - Wallet Picker Sheet

private struct WalletPickerSheet: View {
    let wallets: [LocalWallet]
    @Binding var selected: UUID?
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List(wallets, id: \.serverId) { wallet in
                Button {
                    selected = wallet.serverId
                    isPresented = false
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill((wallet.color.map { Color(hex: $0) } ?? .blue).opacity(0.15))
                                .frame(width: 36, height: 36)
                            Text(walletIcon(wallet)).font(.system(size: 18))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(wallet.name)
                                .foregroundColor(.primary).fontWeight(.medium)
                            Text(wallet.balance.formatted(currency: "VND"))
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        if selected == wallet.serverId {
                            Image(systemName: "checkmark").foregroundColor(.blue)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }

    private func walletIcon(_ w: LocalWallet) -> String {
        if let icon = w.icon, !icon.isEmpty { return icon }
        switch w.type {
        case "cash": return "💵"
        case "bank": return "🏦"
        case "e_wallet": return "📱"
        case "investment": return "📈"
        default: return "💼"
        }
    }
}
