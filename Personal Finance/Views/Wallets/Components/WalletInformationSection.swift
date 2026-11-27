import SwiftUI

struct WalletInformationSection: View {
    let wallet: LocalWallet

    private var language: AppLanguage { AppLocalization.shared.language }

    var body: some View {
        Section("Wallet Details") {
            DetailInfoRow(title: "Type", value: wallet.typeLabel)
            DetailInfoRow(
                title: "Default Wallet",
                value: language.text(wallet.isDefault ? "Yes" : "No")
            )

            if wallet.type == .credit {
                if let statementDay = wallet.statementDay {
                    DetailInfoRow(
                        title: "Statement Day",
                        value: language.text("Day %lld", statementDay)
                    )
                }
                if let paymentDueDay = wallet.paymentDueDay {
                    DetailInfoRow(
                        title: "Payment Due Day",
                        value: language.text("Day %lld", paymentDueDay)
                    )
                }
            }
        }
    }
}
