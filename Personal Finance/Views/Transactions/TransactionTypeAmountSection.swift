import SwiftUI

struct TransactionTypeAmountSection: View {
    @Binding var type: String
    @Binding var amount: Double
    @Binding var amountText: String

    let onTypeChanged: (String) -> Void

    var body: some View {
        Section {
            Picker("Type", selection: $type) {
                Text("Expense").tag("expense")
                Text("Income").tag("income")
            }
            .pickerStyle(.segmented)
            .tint(type == "income" ? .income : .expense)
            .onChange(of: type) { _, newType in
                onTypeChanged(newType)
            }

            CurrencyAmountField(amount: $amount, amountText: $amountText)
        }
    }
}
