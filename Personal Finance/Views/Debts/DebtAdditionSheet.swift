import SwiftUI
import SwiftData

struct DebtAdditionSheet: View {
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
                    walletSectionTitle: "Wallet (optional)"
                )
            }
            .formKeyboardHandling()
            .navigationTitle("Add to \(debt.type == "lend" ? "Lending" : "Borrowing")")
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
                            Task { await add() }
                        }
                        .disabled(amount <= 0)
                    }
                }
            }
            .errorAlert($errorMsg)
        }
    }

    private func add() async {
        isSaving = true
        defer { isSaving = false }

        let wallet = wallets.first { $0.serverId == selectedWalletId }
        do {
            try await DebtService.shared.addAmount(
                to: debt,
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
