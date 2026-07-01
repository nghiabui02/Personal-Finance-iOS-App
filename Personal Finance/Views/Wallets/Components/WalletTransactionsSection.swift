import SwiftUI

struct WalletTransactionsSection: View {
    let transactions: [LocalTransaction]
    var limit = 50

    private var displayedTransactions: ArraySlice<LocalTransaction> {
        transactions.prefix(limit)
    }

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
                    Array(displayedTransactions.enumerated()),
                    id: \.element.serverId
                ) { index, transaction in
                    TransactionRow(
                        transaction: transaction,
                        showDivider: index < displayedTransactions.count - 1
                    )
                }
            }
        }
    }
}
