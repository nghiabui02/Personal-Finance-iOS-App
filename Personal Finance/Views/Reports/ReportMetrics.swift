import SwiftUI

struct NetWorthPoint: Identifiable {
    let id: String
    let date: Date
    let label: String
    let value: Decimal
}

struct ReportMetrics {
    var income: Decimal = 0
    var expense: Decimal = 0
    var currentNetWorth: Decimal = 0
    var cash: Decimal = 0
    var lent: Decimal = 0
    var creditOwed: Decimal = 0
    var borrowed: Decimal = 0
    var chartData: [ReportChartBar] = []
    var spendingBreakdown: [ReportCategoryBreakdown] = []
    var netWorthHistory: [NetWorthPoint] = []
    var monthlyBudgets: [LocalBudget] = []
    var budgetUsage: [UUID: BudgetUsage] = [:]
    var debtFlow = DebtAdjustmentFlow()

    var net: Decimal { income - expense }
    var savingsRate: Double { income > 0 ? (net / income * 100).doubleValue : 0 }

    /// Includes the loan principal that `net` deliberately leaves out.
    var netIncludingDebt: Decimal {
        net + debtFlow.debtIncome - debtFlow.debtExpense
    }
}

/// Money that moved without being earned or spent — shown in its own block so the
/// headline totals can stay strictly about income and spending.
struct DebtAdjustmentFlow {
    /// Borrowing and debt collections.
    var debtIncome: Decimal = 0
    /// Lending and principal repayments.
    var debtExpense: Decimal = 0
    var adjustmentIncome: Decimal = 0
    var adjustmentExpense: Decimal = 0

    var isEmpty: Bool {
        debtIncome == 0 && debtExpense == 0 && adjustmentIncome == 0 && adjustmentExpense == 0
    }
}

struct ReportChartBar: Identifiable {
    let id: String
    let label: String
    let income: Decimal
    let expense: Decimal
}

struct ReportCategoryBreakdown: Identifiable {
    let id: String
    let name: String
    let icon: String
    let amount: Decimal
    let color: Color
    let percentage: Double
}

@MainActor
enum ReportMetricsCalculator {
    /// Takes every kind of transaction in the period plus the category list — it needs
    /// the full set to report debt and adjustment flow alongside the operating totals.
    /// A monthly report also needs the earlier months its rollover budgets carry from.
    static func calculate(
        transactions: [LocalTransaction],
        categories: [LocalCategory],
        wallets: [LocalWallet],
        debts: [LocalDebt],
        budgets: [LocalBudget],
        snapshots: [RemoteNetWorthSnapshot],
        context: ReportPeriodContext
    ) -> ReportMetrics {
        let operating = transactions.operatingOnly(using: categories)
        let txMetrics = calculateTransactionMetrics(transactions: operating, context: context)
        let nw = NetWorth.calculate(wallets: wallets, debts: debts)
        let monthlyBudgets = context.period == .month ? budgets.filter {
            $0.active && context.calendar.isDate($0.month, equalTo: context.referenceDate, toGranularity: .month)
        } : []
        let debtFlow = calculateDebtAdjustmentFlow(
            transactions: transactions, categories: categories, context: context
        )

        return ReportMetrics(
            income: txMetrics.income,
            expense: txMetrics.expense,
            currentNetWorth: nw.total,
            cash: nw.cash,
            lent: nw.lent,
            creditOwed: nw.creditOwed,
            borrowed: nw.borrowed,
            chartData: makeChartBars(buckets: txMetrics.buckets, context: context),
            spendingBreakdown: makeSpendingBreakdown(categoryTotals: txMetrics.categoryTotals),
            netWorthHistory: historyPoints(from: snapshots),
            monthlyBudgets: monthlyBudgets,
            budgetUsage: monthlyBudgets.isEmpty ? [:] : BudgetUsageCalculator.calculate(
                budgets: budgets, operatingTransactions: operating
            ),
            debtFlow: debtFlow
        )
    }

    private static func calculateDebtAdjustmentFlow(
        transactions: [LocalTransaction],
        categories: [LocalCategory],
        context: ReportPeriodContext
    ) -> DebtAdjustmentFlow {
        let calendar = context.calendar
        let range = context.range
        let dayAfterEnd = calendar.date(byAdding: .day, value: 1, to: range.end) ?? range.end
        let keys = categories.systemKeysByCategoryId

        var flow = DebtAdjustmentFlow()
        for tx in transactions {
            guard tx.transactionDate >= range.start, tx.transactionDate < dayAfterEnd else { continue }
            let isIncome = tx.type == .income
            switch tx.reportingGroup(systemKeysByCategoryId: keys) {
            case .debt:
                if isIncome { flow.debtIncome += tx.amount } else { flow.debtExpense += tx.amount }
            case .adjustment:
                if isIncome { flow.adjustmentIncome += tx.amount } else { flow.adjustmentExpense += tx.amount }
            case .operating, .transfer:
                continue
            }
        }
        return flow
    }

    private typealias CategoryTotal = (name: String, icon: String, color: String?, total: Decimal)

    private static func calculateTransactionMetrics(
        transactions: [LocalTransaction],
        context: ReportPeriodContext
    ) -> (
        income: Decimal,
        expense: Decimal,
        buckets: [Date: (income: Decimal, expense: Decimal)],
        categoryTotals: [String: CategoryTotal]
    ) {
        let calendar = context.calendar
        let range = context.range
        let dayAfterEnd = calendar.date(byAdding: .day, value: 1, to: range.end) ?? range.end

        var income: Decimal = 0
        var expense: Decimal = 0
        var buckets: [Date: (income: Decimal, expense: Decimal)] = [:]
        var categoryTotals: [String: CategoryTotal] = [:]

        for tx in transactions {
            let date = tx.transactionDate
            guard date >= range.start && date < dayAfterEnd else { continue }
            guard !tx.isTransfer else { continue }

            let key = bucketKey(for: date, period: context.period, calendar: calendar)
            if tx.type == .income {
                income += tx.amount
                buckets[key, default: (0, 0)].income += tx.amount
            } else {
                expense += tx.amount
                buckets[key, default: (0, 0)].expense += tx.amount
                accumulateExpense(tx, categoryTotals: &categoryTotals)
            }
        }

        return (income, expense, buckets, categoryTotals)
    }

    private static func bucketKey(for date: Date, period: ReportPeriod, calendar: Calendar) -> Date {
        switch period {
        case .week, .month:
            return calendar.startOfDay(for: date)
        case .quarter, .year:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        }
    }

    private static func accumulateExpense(
        _ tx: LocalTransaction,
        categoryTotals: inout [String: CategoryTotal]
    ) {
        let key = tx.categoryId?.uuidString ?? tx.categoryLabel ?? "other"
        let existing = categoryTotals[key]
        categoryTotals[key] = (
            name: existing?.name ?? tx.categoryLabel ?? AppLocalization.shared.language.text("Other"),
            icon: existing?.icon ?? tx.categoryIcon ?? "💸",
            color: existing?.color ?? tx.categoryColor,
            total: (existing?.total ?? 0) + tx.amount
        )
    }

    private static let historyLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d/M"
        formatter.timeZone = LedgerDate.timeZone
        return formatter
    }()

    private static func historyPoints(from snapshots: [RemoteNetWorthSnapshot]) -> [NetWorthPoint] {
        let cutoff = NetWorthHistory.firstDay()
        return snapshots.sorted { $0.recordedDate < $1.recordedDate }.compactMap { row in
            guard row.recordedDate.string >= cutoff else { return nil }
            let date = row.recordedDate.date
            return NetWorthPoint(id: row.recordedDate.string, date: date,
                                 label: historyLabelFormatter.string(from: date), value: row.netWorth)
        }
    }

    private static func makeChartBars(
        buckets: [Date: (income: Decimal, expense: Decimal)],
        context: ReportPeriodContext
    ) -> [ReportChartBar] {
        switch context.period {
        case .week:
            return makeDailyBars(
                count: 7,
                labels: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map { AppLocalization.shared.language.text($0) },
                buckets: buckets,
                context: context
            )
        case .month:
            let dayCount = context.calendar.range(of: .day, in: .month, for: context.referenceDate)?.count ?? 0
            return makeDailyBars(
                count: dayCount,
                labels: (1...max(dayCount, 1)).map(String.init),
                buckets: buckets,
                context: context
            )
        case .quarter:
            return makeMonthlyBars(count: 3, buckets: buckets, context: context)
        case .year:
            return makeMonthlyBars(count: 12, buckets: buckets, context: context)
        }
    }

    private static func makeDailyBars(
        count: Int,
        labels: [String],
        buckets: [Date: (income: Decimal, expense: Decimal)],
        context: ReportPeriodContext
    ) -> [ReportChartBar] {
        let calendar = context.calendar
        return (0..<count).map { i in
            let date = calendar.date(byAdding: .day, value: i, to: context.range.start) ?? context.range.start
            let bucket = buckets[calendar.startOfDay(for: date)] ?? (0, 0)
            return ReportChartBar(id: "\(i)", label: labels[i], income: bucket.income, expense: bucket.expense)
        }
    }

    private static func makeMonthlyBars(
        count: Int,
        buckets: [Date: (income: Decimal, expense: Decimal)],
        context: ReportPeriodContext
    ) -> [ReportChartBar] {
        let calendar = context.calendar
        return (0..<count).map { i in
            let date = calendar.date(byAdding: .month, value: i, to: context.range.start) ?? context.range.start
            let key = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
            let bucket = buckets[key] ?? (0, 0)
            return ReportChartBar(
                id: "\(i)",
                label: date.formatted(LedgerDate.display(.dateTime.month(.abbreviated))),
                income: bucket.income,
                expense: bucket.expense
            )
        }
    }

    private static func makeSpendingBreakdown(
        categoryTotals: [String: CategoryTotal]
    ) -> [ReportCategoryBreakdown] {
        // Shares are of all spending, not of the top eight, so the legend agrees with the total.
        let sorted = categoryTotals.sorted { $0.value.total > $1.value.total }.prefix(8)
        let spendingTotal = categoryTotals.values.reduce(Decimal.zero) { $0 + $1.total }
        let palette: [Color] = [.red, .purple, .orange, .blue, .green, .pink, .indigo, .teal]

        return sorted.enumerated().map { index, entry in
            let item = entry.value
            return ReportCategoryBreakdown(
                id: entry.key,
                name: item.name,
                icon: item.icon,
                amount: item.total,
                color: item.color.map { Color(hex: $0) } ?? palette[index % palette.count],
                percentage: spendingTotal > 0 ? (item.total / spendingTotal * 100).doubleValue : 0
            )
        }
    }
}
