import SwiftUI

struct WalletInformationSection: View {
    let wallet: LocalWallet

    var body: some View {
        Section("Wallet Details") {
            DetailInfoRow(title: "Type", value: wallet.typeLabel)
            DetailInfoRow(
                title: "Default Wallet",
                value: wallet.isDefault ? "Yes" : "No"
            )

            if wallet.type == "credit" {
                if let statementDay = wallet.statementDay {
                    DetailInfoRow(
                        title: "Statement Day",
                        value: "Day \(statementDay)"
                    )
                }
                if let paymentDueDay = wallet.paymentDueDay {
                    DetailInfoRow(
                        title: "Payment Due Day",
                        value: "Day \(paymentDueDay)"
                    )
                }
            }
        }
    }
}
