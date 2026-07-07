import SwiftUI
import SwiftData

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

    private var selectedSourceWallet: LocalWallet? {
        sourceWallets.first { $0.serverId == selectedWalletId }
    }

    private var canPay: Bool {
        amount > 0
            && amount <= creditWallet.amountOwed
            && selectedSourceWallet != nil
            && (selectedSourceWallet?.balance ?? 0) >= amount
    }

    var body: some View {
        NavigationStack {
            Form {
                creditSummarySection
                paymentDetailsSection
                sourceWalletSection
            }
            .formKeyboardHandling()
            .navigationTitle("Pay Credit Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button("Pay") {
                            Task { await pay() }
                        }
                        .disabled(!canPay)
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

    private var creditSummarySection: some View {
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
    }

    private var paymentDetailsSection: some View {
        Section {
            CurrencyAmountField(amount: $amount, amountText: $amountText)

            DatePicker("Date", selection: $date, displayedComponents: .date)
            TextField("Note (optional)", text: $note)
        }
    }

    private var sourceWalletSection: some View {
        Section("Pay From") {
            Picker("Wallet", selection: $selectedWalletId) {
                Text("Select wallet").tag(UUID?.none)
                ForEach(sourceWallets, id: \.serverId) { wallet in
                    Text("\(wallet.displayIcon) \(wallet.name)")
                        .tag(Optional(wallet.serverId))
                }
            }
        }
    }

    private func pay() async {
        guard let selectedSourceWallet else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await WalletService.shared.payCredit(
                creditWallet,
                from: selectedSourceWallet,
                amount: amount,
                date: date,
                note: note.isEmpty ? nil : note,
                in: modelContext
            )
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}
