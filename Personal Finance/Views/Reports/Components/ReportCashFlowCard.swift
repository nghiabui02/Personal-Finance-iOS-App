import SwiftUI

struct ReportCashFlowCard: View {
    let metrics: ReportMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            netAmount
            Divider()
            incomeExpenseSummary
            savingsBar
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("NET CASH FLOW")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
            Spacer()
            savingsBadge
        }
    }

    @ViewBuilder
    private var savingsBadge: some View {
        if metrics.income > 0 {
            if metrics.net >= 0 {
                Text(String(format: "%.1f%% saved", metrics.savingsRate))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.income)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.income.opacity(0.15))
                    .clipShape(Capsule())
            } else {
                Text("over budget")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.expense.opacity(0.85))
                    .clipShape(Capsule())
            }
        }
    }

    private var netAmount: some View {
        Text(netFormatted)
            .font(.system(size: 38, weight: .bold, design: .rounded))
            .foregroundStyle(metrics.net >= 0 ? Color.income : Color.expense)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }

    private var netFormatted: String {
        (metrics.net > 0 ? "+" : "") + metrics.net.formatted(currency: "VND")
    }

    private var incomeExpenseSummary: some View {
        HStack(spacing: 0) {
            ReportAmountSummaryColumn(title: "INCOME", amount: metrics.income, color: .income)
            Divider().frame(height: 32).padding(.horizontal, 16)
            ReportAmountSummaryColumn(title: "EXPENSE", amount: metrics.expense, color: .expense)
            Spacer()
        }
    }

    private var savingsBar: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let ratio = metrics.income > 0
                    ? max(0, min(1, metrics.net / metrics.income))
                    : 0
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.income)
                        .frame(width: geo.size.width * ratio)
                    Rectangle()
                        .fill(Color.expense)
                }
            }
            .frame(height: 6)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            HStack {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.left")
                    Text("savings")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 3) {
                    Text("spending")
                    Image(systemName: "arrow.right")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
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
                .foregroundStyle(.secondary)
                .tracking(0.5)
            Text(amount.formatted(currency: "VND"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
    }
}
