import SwiftUI

struct TransactionTypeAmountSection: View {
    @Binding var type: TransactionKind
    @Binding var amount: Decimal
    @Binding var amountText: String

    let allowsTypeChange: Bool
    let onTypeChanged: (TransactionKind) -> Void

    var body: some View {
        Section {
            Picker("Type", selection: $type) {
                Text("Expense").tag(TransactionKind.expense)
                Text("Income").tag(TransactionKind.income)
            }
            .pickerStyle(.segmented)
            .disabled(!allowsTypeChange)
            .tint(type == .income ? .income : .expense)
            .onChange(of: type) { _, newType in
                onTypeChanged(newType)
            }

            CurrencyAmountField(amount: $amount, amountText: $amountText)

            let suggestions = amountSuggestions(amountText)
            if !suggestions.isEmpty {
                FlowLayout {
                    ForEach(suggestions, id: \.self) { suggestion in
                        SuggestionChip(label: suggestion) {
                            applyAmountFormat(new: suggestion, amountText: &amountText, amount: &amount)
                        }
                    }
                }
                .listRowSeparator(.hidden)
            }
        }
    }
}
