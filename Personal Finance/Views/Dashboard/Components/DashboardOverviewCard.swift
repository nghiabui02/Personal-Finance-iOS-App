import SwiftUI

struct DashboardOverviewCard: View {
    let netBalance: Decimal
    let income: Decimal
    let expense: Decimal
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("NET BALANCE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Text(netBalance.formatted(currency: currency))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(netBalance >= 0 ? Color.income : Color.expense)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .padding()

            Divider()

            HStack(spacing: 0) {
                amountColumn(title: "INCOME", amount: income, color: .income, prefix: "+")
                amountColumn(title: "EXPENSE", amount: expense, color: .expense)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func amountColumn(
        title: LocalizedStringKey,
        amount: Decimal,
        color: Color,
        prefix: String = ""
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
            Text("\(prefix)\(amount.formatted(currency: currency))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}
