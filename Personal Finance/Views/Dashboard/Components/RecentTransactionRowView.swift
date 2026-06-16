import SwiftUI

struct RecentTransactionRowView: View {
    let transaction: LocalTransaction
    let currency: String

    private var iconEmoji: String {
        if let icon = transaction.categoryIcon, !icon.isEmpty { return icon }
        return transaction.type == "income" ? "💰" : "💸"
    }

    private var amountText: String {
        let prefix = transaction.type == "income" ? "+" : "-"
        return "\(prefix)\(transaction.amount.formatted(currency: currency))"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(.systemGray6))
                    .frame(width: 44, height: 44)
                Text(iconEmoji).font(.system(size: 22))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.note ?? transaction.categoryName ?? "Transaction")
                    .font(.subheadline).fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(transaction.walletName)
                    Text("·")
                    Text(transaction.transactionDate.formatted(date: .abbreviated, time: .omitted))
                }
                .font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            Text(amountText)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundColor(transaction.type == "income" ? .green : .red)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
}
