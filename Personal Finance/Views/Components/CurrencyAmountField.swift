import SwiftUI

struct CurrencyAmountField: View {
    let title: LocalizedStringKey
    let currencySymbol: String
    let placeholder: LocalizedStringKey

    @Binding var amount: Decimal
    @Binding var amountText: String

    init(
        title: LocalizedStringKey = "Amount",
        currencySymbol: String = "₫",
        placeholder: LocalizedStringKey = "0",
        amount: Binding<Decimal>,
        amountText: Binding<String>
    ) {
        self.title = title
        self.currencySymbol = currencySymbol
        self.placeholder = placeholder
        _amount = amount
        _amountText = amountText
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(placeholder, text: $amountText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .fontWeight(.semibold)
                .onChange(of: amountText) { oldValue, newValue in
                    applyAmountFormat(
                        old: oldValue,
                        new: newValue,
                        amountText: &amountText,
                        amount: &amount
                    )
                }
            Text(currencySymbol)
                .foregroundStyle(.secondary)
        }
    }
}
