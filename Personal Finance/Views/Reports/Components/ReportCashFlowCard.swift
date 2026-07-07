import SwiftUI

struct ReportCashFlowCard: View {
    let metrics: ReportMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            netAmount
            incomeExpenseSummary
            Divider()
            savingsRateRow
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var header: some View {
        HStack {
            Text("NET CASH FLOW")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .tracking(1)
            Spacer()
            if metrics.net < 0 {
                Text("over budget")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.expense.opacity(0.85))
                    .clipShape(Capsule())
            }
        }
    }

    private var netAmount: some View {
        Text(metrics.net.formatted(currency: "VND"))
            .font(.system(size: 38, weight: .bold, design: .rounded))
            .foregroundColor(metrics.net >= 0 ? .income : .expense)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }

    private var incomeExpenseSummary: some View {
        HStack(spacing: 0) {
            ReportAmountSummaryColumn(
                title: "INCOME",
                amount: metrics.income,
                color: .income
            )

            Divider()
                .frame(height: 32)
                .padding(.horizontal, 16)

            ReportAmountSummaryColumn(
                title: "EXPENSE",
                amount: metrics.expense,
                color: .expense
            )

            Spacer()
        }
    }

    private var savingsRateRow: some View {
        HStack {
            Text("Savings rate")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text("\(metrics.savingsRate, format: .number.precision(.fractionLength(1)))%")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(metrics.savingsRate >= 0 ? .income : .expense)
        }
    }
}

private struct ReportAmountSummaryColumn: View {
    let title: String
    let amount: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .tracking(0.5)
            Text(amount.formatted(currency: "VND"))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
    }
}
