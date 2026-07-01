import SwiftUI

struct DashboardRecentTransactionsSection: View {
    let transactions: [LocalTransaction]
    let isSyncing: Bool
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Transactions")
                .font(.headline)
                .padding(.horizontal)

            if transactions.isEmpty && !isSyncing {
                ContentUnavailableView(
                    "No Transactions",
                    systemImage: "tray",
                    description: Text("Pull down to refresh")
                )
                .padding(.vertical, 8)
            } else {
                transactionList
            }
        }
    }

    private var transactionList: some View {
        let lastId = transactions.last?.serverId
        return VStack(spacing: 0) {
            ForEach(transactions) { transaction in
                RecentTransactionRowView(transaction: transaction, currency: currency)
                if transaction.serverId != lastId {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}
