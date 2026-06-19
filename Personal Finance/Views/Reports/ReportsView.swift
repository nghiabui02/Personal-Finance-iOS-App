import SwiftUI
import SwiftData
import Charts

enum ReportPeriod: String, CaseIterable {
    case week = "Week"
    case month = "Month"
    case quarter = "Quarter"
    case year = "Year"
}

struct ReportsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalTransaction.transactionDate, order: .reverse) private var allTx: [LocalTransaction]
    @StateObject private var sync = SyncManager.shared

    @State private var selectedPeriod: ReportPeriod = .week
    @State private var referenceDate: Date = Date()
    @State private var cachedIncome: Double = 0
    @State private var cachedExpense: Double = 0
    @State private var cachedChartData: [ChartBar] = []
    @State private var cachedBreakdown: [CategoryBreakdown] = []

    private var net: Double { cachedIncome - cachedExpense }

    private var periodRange: (start: Date, end: Date) {
        let cal = Calendar.current
        switch selectedPeriod {
        case .week:
            let weekday = cal.component(.weekday, from: referenceDate)
            let daysFromMon = (weekday - 2 + 7) % 7
            let monday = cal.date(byAdding: .day, value: -daysFromMon, to: cal.startOfDay(for: referenceDate))!
            return (monday, cal.date(byAdding: .day, value: 6, to: monday)!)
        case .month:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: referenceDate))!
            let count = cal.range(of: .day, in: .month, for: referenceDate)!.count
            return (start, cal.date(byAdding: .day, value: count - 1, to: start)!)
        case .quarter:
            let m = cal.component(.month, from: referenceDate)
            var c = cal.dateComponents([.year], from: referenceDate)
            c.month = ((m - 1) / 3) * 3 + 1; c.day = 1
            let start = cal.date(from: c)!
            return (start, cal.date(byAdding: .day, value: -1, to: cal.date(byAdding: .month, value: 3, to: start)!)!)
        case .year:
            var c = cal.dateComponents([.year], from: referenceDate)
            c.month = 1; c.day = 1
            let start = cal.date(from: c)!
            c.month = 12; c.day = 31
            return (start, cal.date(from: c)!)
        }
    }

    private var rangeLabel: String {
        let cal = Calendar.current
        switch selectedPeriod {
        case .week:
            let (s, e) = periodRange
            return "\(s.formatted(.dateTime.month(.abbreviated).day())) – \(e.formatted(.dateTime.month(.abbreviated).day())), \(cal.component(.year, from: e))"
        case .month:
            return referenceDate.formatted(.dateTime.month(.wide).year())
        case .quarter:
            let q = (cal.component(.month, from: periodRange.start) - 1) / 3 + 1
            return "Q\(q) \(cal.component(.year, from: referenceDate))"
        case .year:
            return String(cal.component(.year, from: referenceDate))
        }
    }

    private var isCurrentPeriod: Bool {
        let cal = Calendar.current
        let now = Date()
        switch selectedPeriod {
        case .week:   return cal.isDate(referenceDate, equalTo: now, toGranularity: .weekOfYear)
        case .month:  return cal.isDate(referenceDate, equalTo: now, toGranularity: .month)
        case .quarter:
            let rQ = (cal.component(.month, from: referenceDate) - 1) / 3
            let nQ = (cal.component(.month, from: now) - 1) / 3
            return cal.component(.year, from: referenceDate) == cal.component(.year, from: now) && rQ == nQ
        case .year:   return cal.isDate(referenceDate, equalTo: now, toGranularity: .year)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    periodSelectorView.padding(.horizontal)
                    dateNavigatorView.padding(.horizontal)
                    netCashFlowCard.padding(.horizontal)
                    chartCard.padding(.horizontal)
                    if !cachedBreakdown.isEmpty {
                        breakdownCard.padding(.horizontal)
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
            .onChange(of: selectedPeriod) { _, _ in recompute() }
            .onChange(of: referenceDate)  { _, _ in recompute() }
        }
    }

    // MARK: - Period Selector

    private var periodSelectorView: some View {
        HStack(spacing: 4) {
            ForEach(ReportPeriod.allCases, id: \.self) { period in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedPeriod = period }
                } label: {
                    Text(period.rawValue)
                        .font(.subheadline.weight(selectedPeriod == period ? .semibold : .regular))
                        .foregroundColor(selectedPeriod == period ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Group {
                                if selectedPeriod == period {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(.tertiarySystemGroupedBackground))
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Date Navigator

    private var dateNavigatorView: some View {
        HStack {
            Button { navigatePeriod(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            Text(rangeLabel)
                .font(.subheadline.weight(.medium))
            Spacer()
            Button { navigatePeriod(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(isCurrentPeriod ? Color.secondary.opacity(0.3) : .secondary)
                    .frame(width: 44, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isCurrentPeriod)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Net Cash Flow Card

    private var netCashFlowCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("NET CASH FLOW")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .tracking(1)
                Spacer()
                if net < 0 {
                    Text("over budget")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.expense.opacity(0.85))
                        .clipShape(Capsule())
                }
            }
            Text(net.formatted(currency: "VND"))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundColor(net >= 0 ? .income : .expense)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("INCOME")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                    Text(cachedIncome.formatted(currency: "VND"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.income)
                        .minimumScaleFactor(0.7).lineLimit(1)
                }
                Divider().frame(height: 32).padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 4) {
                    Text("EXPENSE")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                        .tracking(0.5)
                    Text(cachedExpense.formatted(currency: "VND"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.expense)
                        .minimumScaleFactor(0.7).lineLimit(1)
                }
                Spacer()
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Chart Card

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectedPeriod == .week || selectedPeriod == .month
                     ? "DAILY INCOME VS EXPENSE"
                     : "MONTHLY INCOME VS EXPENSE")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .tracking(1)
                Spacer()
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Circle().fill(Color.income).frame(width: 8, height: 8)
                        Text("Income").font(.caption2).foregroundColor(.secondary)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.expense).frame(width: 8, height: 8)
                        Text("Expense").font(.caption2).foregroundColor(.secondary)
                    }
                }
            }

            if cachedChartData.isEmpty {
                Text("No data for this period")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .multilineTextAlignment(.center)
            } else {
                Chart {
                    ForEach(cachedChartData) { bar in
                        BarMark(x: .value("Label", bar.label),
                                y: .value("Income", bar.income / 1_000))
                            .foregroundStyle(Color.income.opacity(0.85))
                            .position(by: .value("Type", "Income"))
                        BarMark(x: .value("Label", bar.label),
                                y: .value("Expense", bar.expense / 1_000))
                            .foregroundStyle(Color.expense.opacity(0.85))
                            .position(by: .value("Type", "Expense"))
                    }
                }
                .chartYAxis {
                    AxisMarks { v in
                        AxisValueLabel {
                            if let d = v.as(Double.self) {
                                Text(compactK(d)).font(.caption2)
                            }
                        }
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    }
                }
                .frame(height: 180)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Spending Breakdown Card

    private var breakdownCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SPENDING BREAKDOWN")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .tracking(1)

            ForEach(cachedBreakdown) { item in
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(item.color.opacity(0.15))
                                .frame(width: 36, height: 36)
                            Text(item.icon).font(.system(size: 18))
                        }
                        Text(item.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "%.0f%%", item.percentage))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 36, alignment: .trailing)
                        Text(item.amount.formatted(currency: "VND"))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(.systemFill))
                                .frame(height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(item.color)
                                .frame(width: max(0, geo.size.width * (item.percentage / 100)), height: 4)
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Period Navigation

    private func navigatePeriod(by delta: Int) {
        let cal = Calendar.current
        let next: Date?
        switch selectedPeriod {
        case .week:    next = cal.date(byAdding: .weekOfYear, value: delta, to: referenceDate)
        case .month:   next = cal.date(byAdding: .month, value: delta, to: referenceDate)
        case .quarter: next = cal.date(byAdding: .month, value: delta * 3, to: referenceDate)
        case .year:    next = cal.date(byAdding: .year, value: delta, to: referenceDate)
        }
        if let next { withAnimation { referenceDate = next } }
    }

    // MARK: - Recompute

    private func recompute() {
        let cal = Calendar.current
        let (rangeStart, rangeEnd) = periodRange
        let dayAfterEnd = cal.date(byAdding: .day, value: 1, to: rangeEnd)!

        var incomeAcc = 0.0, expenseAcc = 0.0
        var catMap: [String: (name: String, icon: String, color: String?, total: Double)] = [:]
        var buckets: [Date: (inc: Double, exp: Double)] = [:]

        for tx in allTx {
            let d = tx.transactionDate
            guard d >= rangeStart && d < dayAfterEnd else { continue }

            let key: Date
            switch selectedPeriod {
            case .week, .month:
                key = cal.startOfDay(for: d)
            case .quarter, .year:
                key = cal.date(from: cal.dateComponents([.year, .month], from: d))!
            }

            if tx.type == "income" {
                incomeAcc += tx.amount
                buckets[key, default: (0, 0)].inc += tx.amount
            } else {
                expenseAcc += tx.amount
                buckets[key, default: (0, 0)].exp += tx.amount
                let catKey = tx.categoryId?.uuidString ?? tx.categoryName ?? "other"
                let ex = catMap[catKey]
                catMap[catKey] = (
                    name: ex?.name ?? tx.categoryName ?? "Other",
                    icon: ex?.icon ?? tx.categoryIcon ?? "💸",
                    color: ex?.color ?? tx.categoryColor,
                    total: (ex?.total ?? 0) + tx.amount
                )
            }
        }

        cachedIncome = incomeAcc
        cachedExpense = expenseAcc

        var bars: [ChartBar] = []
        switch selectedPeriod {
        case .week:
            let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            for i in 0..<7 {
                let date = cal.date(byAdding: .day, value: i, to: rangeStart)!
                let b = buckets[cal.startOfDay(for: date)] ?? (0, 0)
                bars.append(ChartBar(id: "\(i)", label: labels[i], income: b.inc, expense: b.exp))
            }
        case .month:
            let count = cal.range(of: .day, in: .month, for: referenceDate)!.count
            for day in 1...count {
                let date = cal.date(byAdding: .day, value: day - 1, to: rangeStart)!
                let b = buckets[cal.startOfDay(for: date)] ?? (0, 0)
                bars.append(ChartBar(id: "\(day)", label: "\(day)", income: b.inc, expense: b.exp))
            }
        case .quarter:
            for m in 0..<3 {
                let date = cal.date(byAdding: .month, value: m, to: rangeStart)!
                let k = cal.date(from: cal.dateComponents([.year, .month], from: date))!
                let b = buckets[k] ?? (0, 0)
                bars.append(ChartBar(id: "\(m)", label: date.formatted(.dateTime.month(.abbreviated)),
                                     income: b.inc, expense: b.exp))
            }
        case .year:
            for m in 0..<12 {
                let date = cal.date(byAdding: .month, value: m, to: rangeStart)!
                let k = cal.date(from: cal.dateComponents([.year, .month], from: date))!
                let b = buckets[k] ?? (0, 0)
                bars.append(ChartBar(id: "\(m)", label: date.formatted(.dateTime.month(.abbreviated)),
                                     income: b.inc, expense: b.exp))
            }
        }
        cachedChartData = bars

        let sorted = catMap.values.sorted { $0.total > $1.total }.prefix(8)
        let total = sorted.reduce(0.0) { $0 + $1.total }
        let palette: [Color] = [.red, .purple, .orange, .blue, .green, .pink, .indigo, .teal]
        cachedBreakdown = sorted.enumerated().map { i, item in
            CategoryBreakdown(
                id: item.name, name: item.name, icon: item.icon,
                amount: item.total,
                color: item.color.map { Color(hex: $0) } ?? palette[i % palette.count],
                percentage: total > 0 ? item.total / total * 100 : 0
            )
        }
    }

    private func compactK(_ kValue: Double) -> String {
        if kValue == 0 { return "0" }
        if kValue >= 1000 { return "\(Int(kValue / 1000))M" }
        return "\(Int(kValue))K"
    }
}

// MARK: - Data models

private struct ChartBar: Identifiable {
    let id: String
    let label: String
    let income: Double
    let expense: Double
}

private struct CategoryBreakdown: Identifiable {
    let id: String
    let name: String
    let icon: String
    let amount: Double
    let color: Color
    let percentage: Double
}
