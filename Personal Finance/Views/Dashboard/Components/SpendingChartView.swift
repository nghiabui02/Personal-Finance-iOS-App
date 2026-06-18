import SwiftUI
import Charts

struct CategorySpending: Identifiable {
    let id: String
    let name: String
    let icon: String
    let color: Color
    let amount: Double
    var percentage: Double = 0
}

struct SpendingChartView: View {
    let items: [CategorySpending]
    let total: Double
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spending Breakdown")
                .font(.headline)

            if items.isEmpty {
                Text("No expenses recorded")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                HStack(alignment: .center, spacing: 20) {
                    // Donut chart
                    Chart(items) { item in
                        SectorMark(
                            angle: .value("Amount", item.amount),
                            innerRadius: .ratio(0.58),
                            angularInset: 1.5
                        )
                        .foregroundStyle(item.color)
                        .cornerRadius(4)
                    }
                    .frame(width: 130, height: 130)
                    .overlay {
                        VStack(spacing: 2) {
                            Text("Total")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(total.formatted(currency: currency))
                                .font(.system(size: 11, weight: .semibold))
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                                .frame(maxWidth: 90)
                        }
                    }

                    // Legend
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(items) { item in
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(item.color)
                                    .frame(width: 10, height: 10)
                                Text(item.icon)
                                    .font(.caption)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Text("\(Int(item.percentage))% · \(item.amount.formatted(currency: currency))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
        .cardBackground()
    }
}
