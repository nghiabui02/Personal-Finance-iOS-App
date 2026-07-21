import Charts
import SwiftUI

struct ReportIncomeExpenseChartCard: View {
    let period: ReportPeriod
    let data: [ReportChartBar]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            chartBody
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var header: some View {
        HStack {
            Text(period == .week || period == .month
                ? "DAILY INCOME VS EXPENSE"
                : "MONTHLY INCOME VS EXPENSE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)
            Spacer()
            ReportChartLegend()
        }
    }

    @ViewBuilder
    private var chartBody: some View {
        if data.isEmpty {
            Text("No data for this period")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 160)
                .multilineTextAlignment(.center)
        } else {
            Chart {
                ForEach(data) { bar in
                    BarMark(
                        x: .value("Label", bar.label),
                        y: .value("Income", bar.income / 1_000)
                    )
                    .foregroundStyle(Color.income.opacity(0.85))
                    .position(by: .value("Type", "Income"))

                    BarMark(
                        x: .value("Label", bar.label),
                        y: .value("Expense", bar.expense / 1_000)
                    )
                    .foregroundStyle(Color.expense.opacity(0.85))
                    .position(by: .value("Type", "Expense"))
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: xAxisDesiredCount)) {
                    AxisValueLabel()
                        .font(.caption2)
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(compactThousands(amount))
                                .font(.caption2)
                        }
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                }
            }
            .frame(height: 200)
        }
    }

    private var xAxisDesiredCount: Int {
        switch period {
        case .month: return 7
        case .week: return 7
        default: return data.count
        }
    }

    private func compactThousands(_ kValue: Double) -> String {
        if kValue == 0 { return "0 đ" }
        if kValue >= 1000 { return "\(Int(kValue / 1000))M đ" }
        return "\(Int(kValue))K đ"
    }
}

private struct ReportChartLegend: View {
    var body: some View {
        HStack(spacing: 10) {
            legendItem("Income", color: .income)
            legendItem("Expense", color: .expense)
        }
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
