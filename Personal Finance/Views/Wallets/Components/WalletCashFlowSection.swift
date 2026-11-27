import SwiftUI

struct WalletCashFlowSection: View {
    let income: Decimal
    let expense: Decimal

    var body: some View {
        Section("This Month") {
            HStack {
                valueColumn(title: "Income", amount: income, color: .income)
                Divider().frame(height: 36)
                valueColumn(title: "Expense", amount: expense, color: .expense)
            }
            .padding(.vertical, 4)
        }
    }

    private func valueColumn(
        title: LocalizedStringKey,
        amount: Decimal,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(amount.formatted(currency: "VND"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
