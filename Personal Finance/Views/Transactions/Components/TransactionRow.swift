import SwiftUI

struct TransactionRow: View {
    let transaction: LocalTransaction
    var showDivider: Bool = false

    private var isTransfer: Bool { transaction.transferPairId != nil }

    private var icon: String {
        if isTransfer { return "🔄" }
        if let i = transaction.categoryIcon, !i.isEmpty { return i }
        return transaction.type == .income ? "💰" : "💸"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(.systemGray6)).frame(width: 44, height: 44)
                    Text(icon).font(.system(size: 22))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(isTransfer ? AppLocalization.shared.language.text("Transfer")
                         : transaction.note ?? AppLocalization.shared.language.text(transaction.type == .income ? "Income" : "Expense"))
                        .font(.subheadline).fontWeight(.medium).lineLimit(1)
                    HStack(spacing: 4) {
                        if !isTransfer, let catName = transaction.categoryLabel, !catName.isEmpty {
                            Text(catName).lineLimit(1)
                            Text("·")
                        }
                        Text(transaction.walletLabel)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(transaction.type == .income ? "+" : "-")\(transaction.amount.formatted(currency: "VND"))")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(isTransfer ? Color.secondary : (transaction.type == .income ? Color.income : Color.expense))
            }
            .padding(.vertical, 8)

            if showDivider {
                Divider().padding(.leading, 56)
            }
        }
    }
}
