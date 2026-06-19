import SwiftUI
import SwiftData
import Charts

struct ReportsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalTransaction.transactionDate, order: .reverse) private var allTx: [LocalTransaction]
    @StateObject private var sync = SyncManager.shared

    @State private var selectedMonth: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date()))!

    // Cached computed results — recomputed once via recompute(), not on every render
    @State private var cachedIncome: Double = 0
    @State private var cachedExpense: Double = 0
    @State private var cachedLast6Months: [MonthData] = []
    @State private var cachedBreakdown: [CategoryData] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    MonthSelectorView(selectedMonth: $selectedMonth).padding(.horizontal)

                    HStack(spacing: 10) {
                        summaryCard("Income",  cachedIncome,  .income,  "arrow.down.circle.fill")
                        summaryCard("Expense", cachedExpense, .expense, "arrow.up.circle.fill")
                        summaryCard("Net", cachedIncome - cachedExpense,
                                    cachedIncome >= cachedExpense ? .blue : .expense, "equal.circle.fill")
                    }
                    .padding(.horizontal)

                    // Bar chart
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last 6 Months").font(.headline).padding(.horizontal)
                        Chart {
                            ForEach(cachedLast6Months) { data in
                                BarMark(x: .value("Month", data.label),
                                        y: .value("Income", data.income / 1_000_000))
                                .foregroundStyle(Color.income.opacity(0.8)).position(by: .value("Type", "Income"))
                                BarMark(x: .value("Month", data.label),
                                        y: .value("Expense", data.expense / 1_000_000))
                                .foregroundStyle(Color.expense.opacity(0.8)).position(by: .value("Type", "Expense"))
                            }
                        }
                        .chartYAxis { AxisMarks { v in AxisValueLabel {
                            if let d = v.as(Double.self) { Text("\(Int(d))M") }
                        }}}
                        .frame(height: 200)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }

                    // Category breakdown — extract prefix(8) once, no re-computation per row
                    if !cachedBreakdown.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Expense Breakdown").font(.headline).padding(.horizontal)
                            let items = cachedBreakdown            // already capped at 8 in recompute()
                            VStack(spacing: 0) {
                                ForEach(items) { item in
                                    HStack(spacing: 12) {
                                        Text(item.icon).font(.title3).frame(width: 32)
                                        Text(item.name).lineLimit(1)
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(item.amount.formatted(currency: "VND")).fontWeight(.medium)
                                            Text(String(format: "%.1f%%", item.percentage))
                                                .font(.caption).foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.horizontal).padding(.vertical, 10)
                                    if item.id != items.last?.id { Divider().padding(.leading, 56) }
                                }
                            }
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Reports")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .refreshable { await sync.syncAll(modelContext: modelContext) }
            .onAppear { recompute() }
            .onChange(of: allTx)          { _, _ in recompute() }
            .onChange(of: selectedMonth)  { _, _ in recompute() }
        }
    }

    // MARK: - Single-pass recompute

    private func recompute() {
        let cal = Calendar.current

        // Compute boundaries for "last 6 months" window
        let windowStart = cal.date(
            from: cal.dateComponents([.year, .month],
                from: cal.date(byAdding: .month, value: -5, to: selectedMonth)!)
        )!
        let windowEnd = cal.date(byAdding: .month, value: 1, to:
            cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth))!
        )!

        // Single pass over allTx
        var incomeAcc = 0.0, expenseAcc = 0.0
        var catMap: [String: (name: String, icon: String, total: Double)] = [:]
        var monthBuckets: [Date: (inc: Double, exp: Double)] = [:]

        for tx in allTx {
            let txDate = tx.transactionDate
            guard txDate >= windowStart && txDate < windowEnd else { continue }

            let monthKey = cal.date(from: cal.dateComponents([.year, .month], from: txDate))!
            let isCurrentMonth = cal.isDate(txDate, equalTo: selectedMonth, toGranularity: .month)

            if tx.type == "income" {
                if isCurrentMonth { incomeAcc += tx.amount }
                monthBuckets[monthKey, default: (0, 0)].inc += tx.amount
            } else {
                if isCurrentMonth {
                    expenseAcc += tx.amount
                    let key = tx.categoryId?.uuidString ?? "other"
                    let ex = catMap[key]
                    catMap[key] = (
                        name: ex?.name ?? tx.categoryName ?? "Other",
                        icon: ex?.icon ?? tx.categoryIcon ?? "💸",
                        total: (ex?.total ?? 0) + tx.amount
                    )
                }
                monthBuckets[monthKey, default: (0, 0)].exp += tx.amount
            }
        }

        cachedIncome  = incomeAcc
        cachedExpense = expenseAcc

        // Category breakdown — capped at 8, stable id = category name
        let sortedCats = catMap.values.sorted { $0.total > $1.total }.prefix(8)
        let catTotal = sortedCats.reduce(0) { $0 + $1.total }
        let palette: [Color] = [.blue, .indigo, .purple, .pink, .orange, .red, .green, .teal]
        cachedBreakdown = sortedCats.enumerated().map { i, item in
            CategoryData(id: item.name, name: item.name, icon: item.icon,
                        amount: item.total, color: palette[i % palette.count],
                        percentage: catTotal > 0 ? item.total / catTotal * 100 : 0)
        }

        // Last 6 months — stable id = month label + year
        cachedLast6Months = (0..<6).reversed().map { offset in
            let month = cal.date(byAdding: .month, value: -offset, to: selectedMonth)!
            let key   = cal.date(from: cal.dateComponents([.year, .month], from: month))!
            let bucket = monthBuckets[key] ?? (0, 0)
            let label  = month.formatted(.dateTime.month(.abbreviated))
            let year   = cal.component(.year, from: month)
            return MonthData(id: "\(label)\(year)", label: label,
                            income: bucket.inc, expense: bucket.exp)
        }
    }

    // MARK: - Summary card

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

// MARK: - Data models — stable IDs (no UUID())

private struct MonthData: Identifiable {
    let id: String       // e.g. "Jun2026"
    let label: String
    let income: Double
    let expense: Double
}

private struct CategoryData: Identifiable {
    let id: String       // category name — stable across renders
    let name: String
    let icon: String
    let amount: Double
    let color: Color
    let percentage: Double
}
