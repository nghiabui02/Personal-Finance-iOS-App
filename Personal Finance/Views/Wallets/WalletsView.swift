import SwiftUI
import SwiftData

struct WalletsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalWallet.name) private var wallets: [LocalWallet]
    @StateObject private var sync = SyncManager.shared

    @State private var showAdd = false
    @State private var showTransfer = false
    @State private var transferSourceWalletId: UUID?
    @State private var payingCreditWallet: LocalWallet?
    @State private var pendingDeletion: LocalWallet?
    @State private var showDeleteConfirmation = false
    @State private var errorMsg: String?

    private var totalBalance: Double {
        let nonCredit = wallets.filter { $0.type != "credit" }.reduce(0.0) { $0 + $1.balance }
        let creditDebt = wallets.filter { $0.type == "credit" }.reduce(0.0) { $0 + $1.amountOwed }
        return nonCredit - creditDebt
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Net Worth")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(totalBalance.formatted(currency: "VND"))
                                .font(.system(.title2, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundColor(totalBalance >= 0 ? .primary : .red)
                        }
                        Spacer()
                        Image(systemName: "creditcard.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .padding(.vertical, 4)
                }

                Section(wallets.isEmpty ? "" : "\(wallets.count) wallets") {
                    if wallets.isEmpty {
                        ContentUnavailableView(
                            "No Wallets",
                            systemImage: "creditcard",
                            description: Text("Tap + to add your first wallet")
                        )
                        .padding(.vertical)
                    } else {
                        ForEach(wallets, id: \.serverId) { wallet in
                            NavigationLink {
                                WalletDetailView(wallet: wallet)
                            } label: {
                                WalletRow(wallet: wallet)
                            }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    if wallets.count >= 2 {
                                        Button {
                                            transferSourceWalletId = wallet.serverId
                                            showTransfer = true
                                        } label: {
                                            Label("Transfer", systemImage: "arrow.left.arrow.right")
                                        }
                                        .tint(.blue)
                                    }
                                    if wallet.type == "credit" {
                                        Button {
                                            payingCreditWallet = wallet
                                        } label: {
                                            Label("Pay Bill", systemImage: "creditcard.fill")
                                        }
                                        .tint(.green)
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        pendingDeletion = wallet
                                        showDeleteConfirmation = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(.red)
                                }
                        }
                    }
                }
            }
            .navigationTitle("Wallets")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if wallets.count >= 2 {
                        Button {
                            transferSourceWalletId = nil
                            showTransfer = true
                        } label: {
                            Label("Transfer", systemImage: "arrow.left.arrow.right")
                                .labelStyle(.titleAndIcon)
                                .font(.subheadline)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .refreshable { await sync.syncAll(modelContext: modelContext) }
            .sheet(isPresented: $showAdd) {
                AddEditWalletView(wallet: nil)
            }
            .sheet(
                isPresented: $showTransfer,
                onDismiss: { transferSourceWalletId = nil }
            ) {
                TransferSheet(
                    wallets: wallets,
                    initialFromWalletId: transferSourceWalletId
                )
            }
            .sheet(item: $payingCreditWallet) { w in
                CreditPaymentSheet(creditWallet: w, wallets: wallets)
            }
            .deleteConfirmation(
                item: $pendingDeletion,
                isPresented: $showDeleteConfirmation,
                title: "Delete Wallet?",
                message: "The wallet will be permanently deleted. Any positive balance may be moved to your default wallet."
            ) { wallet in
                Task { await deleteWallet(wallet) }
            }
            .errorAlert($errorMsg)
        }
    }

    private func deleteWallet(_ wallet: LocalWallet) async {
        do {
            try await WalletService.shared.delete(wallet, in: modelContext)
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}

// MARK: - Wallet Row

struct WalletRow: View {
    let wallet: LocalWallet

    var accentColor: Color {
        wallet.color.map { Color(hex: $0) } ?? .blue
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Text(wallet.displayIcon).font(.system(size: 22))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(wallet.name)
                        .font(.subheadline).fontWeight(.medium)
                    if wallet.isDefault {
                        StatusBadge(label: "Default", color: .blue)
                    }
                }
                if wallet.type == "credit" {
                    Text("Used: \(wallet.amountOwed.formatted(currency: "VND")) / \((wallet.creditLimit ?? 0).formatted(currency: "VND"))")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Text(wallet.typeLabel)
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(wallet.balance.formatted(currency: "VND"))
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(wallet.type == "credit" ? .income : (wallet.balance < 0 ? .red : .primary))
                if wallet.type == "credit" {
                    Text("available")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Credit Payment Sheet

struct CreditPaymentSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let creditWallet: LocalWallet
    let wallets: [LocalWallet]

    @State private var amount: Double = 0
    @State private var amountText = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var selectedWalletId: UUID?
    @State private var isSaving = false
    @State private var errorMsg: String?

    private var sourceWallets: [LocalWallet] {
        wallets.filter { $0.serverId != creditWallet.serverId && $0.type != "credit" }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Outstanding")
                        Spacer()
                        Text(creditWallet.amountOwed.formatted(currency: "VND"))
                            .foregroundColor(.expense)
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Credit Limit")
                        Spacer()
                        Text((creditWallet.creditLimit ?? 0).formatted(currency: "VND"))
                            .foregroundColor(.secondary)
                    }
                }

                Section {
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
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
                }

                Section("Pay From") {
                    Picker("Wallet", selection: $selectedWalletId) {
                        Text("Select wallet").tag(UUID?.none)
                        ForEach(sourceWallets, id: \.serverId) { w in
                            Text("\(w.displayIcon) \(w.name)").tag(Optional(w.serverId))
                        }
                    }
                }
            }
            .formKeyboardHandling()
            .navigationTitle("Pay Credit Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView().scaleEffect(0.8) }
                    else {
                        Button("Pay") { Task { await pay() } }
                            .disabled(
                                amount <= 0
                                || amount > creditWallet.amountOwed
                                || selectedWalletId == nil
                                || (sourceWallets.first(where: { $0.serverId == selectedWalletId })?.balance ?? 0) < amount
                            )
                    }
                }
            }
            .errorAlert($errorMsg)
        }
        .onAppear {
            selectedWalletId = sourceWallets.first(where: { $0.isDefault })?.serverId
                ?? sourceWallets.first?.serverId
        }
    }

    private func pay() async {
        guard let walletId = selectedWalletId,
              let sourceWallet = wallets.first(where: { $0.serverId == walletId }) else { return }
        isSaving = true; defer { isSaving = false }
        do {
            try await WalletService.shared.payCredit(
                creditWallet, from: sourceWallet,
                amount: amount, date: date,
                note: note.isEmpty ? nil : note,
                in: modelContext
            )
            dismiss()
        } catch { errorMsg = error.localizedDescription }
    }
}
