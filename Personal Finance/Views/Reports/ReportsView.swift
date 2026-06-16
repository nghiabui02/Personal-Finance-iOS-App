import SwiftUI
import SwiftData
import Charts

struct ReportsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalTransaction.transactionDate, order: .reverse) private var allTx: [LocalTransaction]
    @StateObject private var sync = SyncManager.shared

    @State private var selectedMonth: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date()))!

    private var monthlyTx: [LocalTransaction] {
        let cal = Calendar.current
        return allTx.filter { cal.isDate($0.transactionDate, equalTo: selectedMonth, toGranularity: .month) }
    }

    private var income: Double { monthlyTx.filter { $0.type == "income" }.reduce(0) { $0 + $1.amount } }
    private var expense: Double { monthlyTx.filter { $0.type == "expense" }.reduce(0) { $0 + $1.amount } }

    // Last 6 months data for bar chart
    private var last6Months: [MonthData] {
        let cal = Calendar.current
        return (0..<6).reversed().map { offset in
            let month = cal.date(byAdding: .month, value: -offset, to: selectedMonth)!
            let txs = allTx.filter { cal.isDate($0.transactionDate, equalTo: month, toGranularity: .month) }
            let inc = txs.filter { $0.type == "income" }.reduce(0) { $0 + $1.amount }
            let exp = txs.filter { $0.type == "expense" }.reduce(0) { $0 + $1.amount }
            let label = month.formatted(.dateTime.month(.abbreviated))
            return MonthData(label: label, income: inc, expense: exp)
        }
    }

    // Expense by category pie
    private var categoryBreakdown: [CategoryData] {
        var grouped: [String: (name: String, icon: String, total: Double)] = [:]
        for tx in monthlyTx where tx.type == "expense" {
            let key = tx.categoryId?.uuidString ?? "other"
            let ex = grouped[key]
            grouped[key] = (name: ex?.name ?? tx.categoryName ?? "Other",
                           icon: ex?.icon ?? tx.categoryIcon ?? "💸",
                           total: (ex?.total ?? 0) + tx.amount)
        }
        let sorted = grouped.values.sorted { $0.total > $1.total }
        let total = sorted.reduce(0) { $0 + $1.total }
        let palette: [Color] = [.blue, .indigo, .purple, .pink, .orange, .red, .green, .teal]
        return sorted.enumerated().map { i, item in
            CategoryData(name: item.name, icon: item.icon,
                        amount: item.total, color: palette[i % palette.count],
                        percentage: total > 0 ? item.total / total * 100 : 0)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    MonthSelectorView(selectedMonth: $selectedMonth).padding(.horizontal)

                    // Summary cards
                    HStack(spacing: 10) {
                        summaryCard("Income", income, .green, "arrow.down.circle.fill")
                        summaryCard("Expense", expense, .red, "arrow.up.circle.fill")
                        summaryCard("Net", income - expense, income >= expense ? .blue : .red, "equal.circle.fill")
                    }
                    .padding(.horizontal)

                    // Bar chart: last 6 months
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last 6 Months").font(.headline).padding(.horizontal)
                        Chart {
                            ForEach(last6Months) { data in
                                BarMark(x: .value("Month", data.label),
                                        y: .value("Income", data.income / 1_000_000))
                                .foregroundStyle(Color.green.opacity(0.8)).position(by: .value("Type", "Income"))
                                BarMark(x: .value("Month", data.label),
                                        y: .value("Expense", data.expense / 1_000_000))
                                .foregroundStyle(Color.red.opacity(0.8)).position(by: .value("Type", "Expense"))
                            }
                        }
                        .chartYAxis { AxisMarks { v in AxisValueLabel { if let d = v.as(Double.self) { Text("\(Int(d))M") } } } }
                        .frame(height: 200)
                        .padding(.horizontal)
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    // Expense breakdown
                    if !categoryBreakdown.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Expense Breakdown").font(.headline).padding(.horizontal)
                            VStack(spacing: 0) {
                                ForEach(categoryBreakdown.prefix(8)) { item in
                                    HStack(spacing: 12) {
                                        Text(item.icon).font(.title3).frame(width: 32)
                                        Text(item.name).lineLimit(1)
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(item.amount.formatted(currency: "VND"))
                                                .fontWeight(.medium)
                                            Text(String(format: "%.1f%%", item.percentage))
                                                .font(.caption).foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.horizontal).padding(.vertical, 10)
                                    if item.name != categoryBreakdown.prefix(8).last?.name {
                                        Divider().padding(.leading, 56)
                                    }
                                }
                            }
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Reports")
            .refreshable { await sync.syncAll(modelContext: modelContext) }
        }
    }

    @ViewBuilder
    private func summaryCard(_ title: String, _ amount: Double, _ color: Color, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundColor(color).font(.caption)
                Text(title).font(.caption).foregroundColor(.secondary)
            }
            Text(amount.formatted(currency: "VND"))
                .font(.system(.subheadline, design: .rounded)).fontWeight(.semibold)
                .foregroundColor(color).minimumScaleFactor(0.5).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12).background(Color(.systemBackground)).cornerRadius(12)
    }
}

private struct MonthData: Identifiable {
    let id = UUID()
    let label: String
    let income: Double
    let expense: Double
}

private struct CategoryData: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let amount: Double
    let color: Color
    let percentage: Double
}
