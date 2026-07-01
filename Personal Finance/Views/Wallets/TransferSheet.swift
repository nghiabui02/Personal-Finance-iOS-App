import SwiftUI
import SwiftData

struct TransferSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let wallets: [LocalWallet]
    let initialFromWalletId: UUID?

    init(wallets: [LocalWallet], initialFromWalletId: UUID? = nil) {
        self.wallets = wallets
        self.initialFromWalletId = initialFromWalletId
    }

    @State private var fromWalletId: UUID?
    @State private var toWalletId: UUID?
    @State private var amount: Double = 0
    @State private var amountText = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var isTransferring = false
    @State private var errorMsg: String?

    private var fromWallet: LocalWallet? { wallets.first { $0.serverId == fromWalletId } }
    private var toWallet: LocalWallet? { wallets.first { $0.serverId == toWalletId } }

    private var availableToWallets: [LocalWallet] {
        wallets.filter { $0.serverId != fromWalletId }
    }

    private var isSourceLocked: Bool {
        wallets.contains { $0.serverId == initialFromWalletId }
    }

    private var insufficientFunds: Bool {
        guard let w = fromWallet, amount > 0 else { return false }
        return w.balance < amount
    }

    private var canTransfer: Bool {
        fromWalletId != nil && toWalletId != nil
        && fromWalletId != toWalletId
        && amount > 0
        && !insufficientFunds
    }

    var body: some View {
        NavigationStack {
            Form {
                fromSection
                toSection
                amountSection

                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...3)
                }
            }
            .formKeyboardHandling()
            .navigationTitle("Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isTransferring {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button("Transfer") {
                            Task { await doTransfer() }
                        }
                        .disabled(!canTransfer)
                        .fontWeight(.semibold)
                    }
                }
            }
            .errorAlert($errorMsg)
        }
        .onAppear {
            let requestedSource = wallets.first {
                $0.serverId == initialFromWalletId
            }?.serverId
            fromWalletId = requestedSource ?? wallets.first?.serverId
            toWalletId = wallets.first {
                $0.serverId != fromWalletId
            }?.serverId
        }
    }

    // MARK: - Sections

    private var fromSection: some View {
        Section("From") {
            if isSourceLocked, let wallet = fromWallet {
                HStack {
                    Text("Wallet")
                    Spacer()
                    walletLabel(wallet)
                        .foregroundColor(.secondary)
                }
            } else {
                Picker("Wallet", selection: $fromWalletId) {
                    Text("Select wallet").tag(Optional<UUID>.none)
                    ForEach(wallets, id: \.serverId) { w in
                        walletLabel(w).tag(Optional(w.serverId))
                    }
                }
                .onChange(of: fromWalletId) { _, newFrom in
                    if toWalletId == newFrom {
                        toWalletId = wallets.first { $0.serverId != newFrom }?.serverId
                    }
                }
            }

            if let w = fromWallet {
                balanceRow(label: "Balance", amount: w.balance)
                if amount > 0 {
                    balanceRow(
                        label: "After transfer",
                        amount: w.balance - amount,
                        highlight: insufficientFunds
                    )
                }
            }

            if insufficientFunds {
                Label("Insufficient funds", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.expense)
            }
        }
    }

    private var toSection: some View {
        Section("To") {
            Picker("Wallet", selection: $toWalletId) {
                Text("Select wallet").tag(Optional<UUID>.none)
                ForEach(availableToWallets, id: \.serverId) { w in
                    walletLabel(w).tag(Optional(w.serverId))
                }
            }

            if let w = toWallet, amount > 0 {
                balanceRow(label: "After transfer", amount: w.balance + amount)
            }
        }
    }

    private var amountSection: some View {
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
        }
    }

    // MARK: - Helpers

    private func walletLabel(_ w: LocalWallet) -> Text {
        Text("\(w.displayIcon) \(w.name)")
    }

    @ViewBuilder
    private func balanceRow(label: String, amount: Double, highlight: Bool = false) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(amount.formatted(currency: "VND"))
                .foregroundColor(highlight ? .expense : .secondary)
        }
        .font(.caption)
    }

    // MARK: - Action

    private func doTransfer() async {
        guard let from = fromWallet, let to = toWallet else { return }
        isTransferring = true
        defer { isTransferring = false }
        do {
            try await TransferService.shared.transfer(
                from: from, to: to,
                amount: amount, date: date,
                note: note.isEmpty ? nil : note,
                in: modelContext
            )
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}
