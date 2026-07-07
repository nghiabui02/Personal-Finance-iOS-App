import SwiftUI

struct DebtAmountEntrySection: View {
    @Binding var amount: Double
    @Binding var amountText: String
    @Binding var date: Date
    @Binding var note: String
    @Binding var selectedWalletId: UUID?

    let wallets: [LocalWallet]
    let walletSectionTitle: String

    var body: some View {
        amountSection
        walletSection
    }

    private var amountSection: some View {
        Section {
            CurrencyAmountField(amount: $amount, amountText: $amountText)

            DatePicker("Date", selection: $date, displayedComponents: .date)
            TextField("Note (optional)", text: $note)
        }
    }

    private var walletSection: some View {
        Section(walletSectionTitle) {
            Picker("Wallet", selection: $selectedWalletId) {
                Text("None").tag(UUID?.none)
                ForEach(wallets, id: \.serverId) { wallet in
                    Text(wallet.name)
                        .tag(Optional(wallet.serverId))
                }
            }
        }
    }
}
