import SwiftUI
import SwiftData

struct ReconcileSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var categories: [LocalCategory]

    let wallet: LocalWallet

    @State private var actualBalance: Double = 0
    @State private var actualBalanceText = ""
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorMsg: String?

    private var delta: Double { actualBalance - wallet.balance }
    private var trackedLabel: String { wallet.type == "credit" ? "Tracked Available Credit" : "Tracked Balance" }
    private var actualLabel: String { wallet.type == "credit" ? "Actual Available Credit" : "Actual Balance" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(trackedLabel)
                        Spacer()
                        Text(wallet.balance.formatted(currency: "VND")).foregroundColor(.secondary)
                    }
                }
                Section {
                    CurrencyAmountField(title: actualLabel, amount: $actualBalance, amountText: $actualBalanceText)
                    if delta != 0 {
                        HStack {
                            Text(delta > 0 ? "Will record as income" : "Will record as expense")
                                .font(.caption)
                            Spacer()
                            Text(abs(delta).formatted(currency: "VND"))
                                .font(.caption).fontWeight(.semibold)
                                .foregroundColor(delta > 0 ? .income : .expense)
                        }
                    }
                }
                Section {
                    TextField("Note (optional)", text: $note)
                }
            }
            .formKeyboardHandling()
            .navigationTitle("Reconcile Balance")
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
                            .disabled(delta == 0)
                    }
                }
            }
            .errorAlert($errorMsg)
        }
        .onAppear {
            actualBalance = wallet.balance
            actualBalanceText = wallet.balance.formattedDecimal()
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await WalletService.shared.reconcile(
                wallet, actualBalance: actualBalance,
                note: note, categories: categories,
                in: modelContext
            )
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}
