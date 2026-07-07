import SwiftUI
import SwiftData

struct DebtPaymentSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let debt: LocalDebt
    let wallets: [LocalWallet]

    @State private var amount: Double = 0
    @State private var amountText = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var selectedWalletId: UUID?
    @State private var isSaving = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationStack {
            Form {
                DebtAmountEntrySection(
                    amount: $amount,
                    amountText: $amountText,
                    date: $date,
                    note: $note,
                    selectedWalletId: $selectedWalletId,
                    wallets: wallets,
                    walletSectionTitle: "Wallet"
                )
            }
            .formKeyboardHandling()
            .navigationTitle("Record Payment")
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
                        Button("Save") {
                            Task { await pay() }
                        }
                        .disabled(amount <= 0 || amount > debt.remainingAmount)
                    }
                }
            }
            .errorAlert($errorMsg)
        }
    }

    private func pay() async {
        isSaving = true
        defer { isSaving = false }

        let wallet = wallets.first { $0.serverId == selectedWalletId }
        do {
            try await DebtService.shared.recordPayment(
                debt,
                amount: amount,
                note: note.isEmpty ? nil : note,
                date: date,
                wallet: wallet,
                in: modelContext
            )
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}
