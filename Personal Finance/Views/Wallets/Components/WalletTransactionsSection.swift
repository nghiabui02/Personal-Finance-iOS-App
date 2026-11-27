import SwiftUI

struct WalletTransactionsSection: View {
    /// The caller fetches at most this many, newest first.
    static let limit = 50

    let transactions: [LocalTransaction]

    var body: some View {
        Section("Transactions") {
            if transactions.isEmpty {
                ContentUnavailableView(
                    "No Transactions",
                    systemImage: "tray",
                    description: Text("Transactions made with this wallet appear here.")
                )
                .padding(.vertical)
            } else {
                ForEach(
                    Array(transactions.enumerated()),
                    id: \.element.serverId
                ) { index, transaction in
                    TransactionRow(
                        transaction: transaction,
                        showDivider: index < transactions.count - 1
                    )
                }
            }
        }
    }
}
