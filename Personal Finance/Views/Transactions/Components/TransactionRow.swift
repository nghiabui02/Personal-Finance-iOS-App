import SwiftUI

struct TransactionRow: View {
    let transaction: LocalTransaction
    var showDivider: Bool = false

    private var isTransfer: Bool { transaction.transferPairId != nil }

    private var icon: String {
        if isTransfer { return "🔄" }
        if let i = transaction.categoryIcon, !i.isEmpty { return i }
        return transaction.type == "income" ? "💰" : "💸"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(.systemGray6)).frame(width: 44, height: 44)
                    Text(icon).font(.system(size: 22))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(isTransfer ? "Transfer" : (transaction.note ?? (transaction.type == "income" ? "Income" : "Expense")))
                        .font(.subheadline).fontWeight(.medium).lineLimit(1)
                    HStack(spacing: 4) {
                        if !isTransfer, let catName = transaction.categoryName, !catName.isEmpty {
                            Text(catName).lineLimit(1)
                            Text("·")
                        }
                        Text(transaction.walletName)
                    }
                    .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text("\(transaction.type == "income" ? "+" : "-")\(transaction.amount.formatted(currency: "VND"))")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(isTransfer ? .secondary : (transaction.type == "income" ? .income : .expense))
            }
            .padding(.vertical, 8)

            if showDivider {
                Divider().padding(.leading, 56)
            }
        }
    }
}
