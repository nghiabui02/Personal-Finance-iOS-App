import SwiftUI
import SwiftData

struct ReconcileSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let wallet: LocalWallet

    /// The amount field takes digits only, so the sign of an overdrawn balance (or a card
    /// past its limit) is a separate toggle.
    @State private var enteredAmount: Decimal = 0
    @State private var enteredAmountText = ""
    @State private var isNegative = false
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorMsg: String?

    private var actualBalance: Decimal { isNegative ? -enteredAmount : enteredAmount }
    private var delta: Decimal { actualBalance - wallet.balance }
    private var trackedLabel: LocalizedStringKey { wallet.type == .credit ? "Tracked Available Credit" : "Tracked Balance" }
    private var actualLabel: LocalizedStringKey { wallet.type == .credit ? "Actual Available Credit" : "Actual Balance" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(trackedLabel)
                        Spacer()
                        Text(wallet.balance.formatted(currency: "VND")).foregroundStyle(.secondary)
                    }
                }
                Section {
                    CurrencyAmountField(title: actualLabel, amount: $enteredAmount, amountText: $enteredAmountText)
                    Toggle("Negative Balance", isOn: $isNegative)
                    if delta != 0 {
                        HStack {
                            Text(delta > 0 ? "Will record as income" : "Will record as expense")
                                .font(.caption)
                            Spacer()
                            Text(abs(delta).formatted(currency: "VND"))
                                .font(.caption).fontWeight(.semibold)
                                .foregroundStyle(delta > 0 ? Color.income : Color.expense)
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
                    Button("Cancel") { dismiss() }.disabled(isSaving)
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
            .interactiveDismissDisabled(isSaving)
        }
        .onAppear {
            isNegative = wallet.balance < 0
            enteredAmount = abs(wallet.balance)
            enteredAmountText = enteredAmount.formattedDecimal()
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await WalletService.shared.reconcile(
                wallet, actualBalance: actualBalance,
                note: note,
                in: modelContext
            )
            Haptics.moneyRecorded()
            dismiss()
        } catch {
            errorMsg = error.asDisplayableError().localizedDescription
        }
    }
}
