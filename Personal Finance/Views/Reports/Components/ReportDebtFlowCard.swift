import SwiftUI

/// Money that moved without being earned or spent. Kept out of the headline
/// totals, but shown here so the period still accounts for every movement.
struct ReportDebtFlowCard: View {
    let flow: DebtAdjustmentFlow
    let netIncludingDebt: Double

    private let columns = [
        GridItem(.flexible(), alignment: .leading),
        GridItem(.flexible(), alignment: .leading),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DEBT CASH FLOW AND BALANCE ADJUSTMENTS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                entry("Borrowing and debt collections", flow.debtIncome, .income)
                entry("Lending and principal repayments", flow.debtExpense, .expense)
                entry("Balance increases", flow.adjustmentIncome, .income)
                entry("Balance decreases", flow.adjustmentExpense, .expense)
            }

            Divider()

            HStack {
                Text("Net cash flow including debt")
                    .font(.subheadline)
                Spacer()
                Text(netIncludingDebt.formatted(currency: "VND"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(netIncludingDebt >= 0 ? Color.income : Color.expense)
            }

            Text("Loan principal and balance adjustments are excluded from income, spending and savings rate. Transfers and credit card principal payments stay in wallet history.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func entry(_ label: String, _ amount: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(amount.formatted(currency: "VND"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
    }
}
