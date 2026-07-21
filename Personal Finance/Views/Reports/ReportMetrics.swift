import SwiftUI

struct NetWorthPoint: Identifiable {
    let id: String
    let date: Date
    let label: String
    let value: Double
}

struct ReportMetrics {
    var income: Double = 0
    var expense: Double = 0
    var currentNetWorth: Double = 0
    var cash: Double = 0
    var lent: Double = 0
    var creditOwed: Double = 0
    var borrowed: Double = 0
    var chartData: [ReportChartBar] = []
    var spendingBreakdown: [ReportCategoryBreakdown] = []
    var netWorthHistory: [NetWorthPoint] = []

    var net: Double { income - expense }
    var savingsRate: Double { income > 0 ? net / income * 100 : 0 }
}

struct ReportChartBar: Identifiable {
    let id: String
    let label: String
    let income: Double
    let expense: Double
}

struct ReportCategoryBreakdown: Identifiable {
    let id: String
    let name: String
    let icon: String
    let amount: Double
    let color: Color
    let percentage: Double
}

enum ReportMetricsCalculator {
    static func calculate(
        transactions: [LocalTransaction],
        wallets: [LocalWallet],
        debts: [LocalDebt],
        context: ReportPeriodContext
    ) -> ReportMetrics {
        let txMetrics = calculateTransactionMetrics(transactions: transactions, context: context)
        let nw = calculateNetWorthComponents(wallets: wallets, debts: debts)
        let history = computeNetWorthHistory(transactions: transactions, currentNW: nw.total)

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
            netWorthHistory: history
        )
    }

    private typealias CategoryTotal = (name: String, icon: String, color: String?, total: Double)

    private static func calculateTransactionMetrics(
        transactions: [LocalTransaction],
        context: ReportPeriodContext
    ) -> (
        income: Double,
        expense: Double,
        buckets: [Date: (income: Double, expense: Double)],
        categoryTotals: [String: CategoryTotal]
    ) {
        let calendar = context.calendar
        let range = context.range
        let dayAfterEnd = calendar.date(byAdding: .day, value: 1, to: range.end) ?? range.end

        var income = 0.0
        var expense = 0.0
        var buckets: [Date: (income: Double, expense: Double)] = [:]
        var categoryTotals: [String: CategoryTotal] = [:]

        for tx in transactions {
            let date = tx.transactionDate
            guard date >= range.start && date < dayAfterEnd else { continue }
            guard !tx.isTransfer else { continue }

            let key = bucketKey(for: date, period: context.period, calendar: calendar)
            if tx.type == "income" {
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
        let key = tx.categoryId?.uuidString ?? tx.categoryName ?? "other"
        let existing = categoryTotals[key]
        categoryTotals[key] = (
            name: existing?.name ?? tx.categoryName ?? "Other",
            icon: existing?.icon ?? tx.categoryIcon ?? "💸",
            color: existing?.color ?? tx.categoryColor,
            total: (existing?.total ?? 0) + tx.amount
        )
    }

    private static func calculateNetWorthComponents(
        wallets: [LocalWallet],
        debts: [LocalDebt]
    ) -> (total: Double, cash: Double, lent: Double, creditOwed: Double, borrowed: Double) {
        let cash = wallets.filter { $0.type != "credit" }.reduce(0) { $0 + $1.balance }
        let creditOwed = wallets.filter { $0.type == "credit" }.reduce(0) { $0 + $1.amountOwed }
        let activeDebts = debts.filter { $0.status != "completed" }
        let lent = activeDebts.filter { $0.type == "lend" }.reduce(0) { $0 + $1.remainingAmount }
        let borrowed = activeDebts.filter { $0.type == "borrow" }.reduce(0) { $0 + $1.remainingAmount }
        return (cash + lent - creditOwed - borrowed, cash, lent, creditOwed, borrowed)
    }

    private static func computeNetWorthHistory(
        transactions: [LocalTransaction],
        currentNW: Double,
        count: Int = 10
    ) -> [NetWorthPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let fmt = DateFormatter()
        fmt.dateFormat = "d/M"

        let nonTransfers = transactions.filter { !$0.isTransfer }

        return (0..<count).reversed().map { weekAgo in
            let checkDate = calendar.date(byAdding: .weekOfYear, value: -weekAgo, to: today) ?? today
            let checkDay = calendar.startOfDay(for: checkDate)

            let delta = nonTransfers
                .filter { calendar.startOfDay(for: $0.transactionDate) > checkDay }
                .reduce(0.0) { acc, tx in
                    tx.type == "income" ? acc + tx.amount : acc - tx.amount
                }
            return NetWorthPoint(
                id: fmt.string(from: checkDate),
                date: checkDay,
                label: fmt.string(from: checkDate),
                value: currentNW - delta
            )
        }
    }

    private static func makeChartBars(
        buckets: [Date: (income: Double, expense: Double)],
        context: ReportPeriodContext
    ) -> [ReportChartBar] {
        switch context.period {
        case .week:
            return makeDailyBars(
                count: 7,
                labels: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
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
        buckets: [Date: (income: Double, expense: Double)],
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
        buckets: [Date: (income: Double, expense: Double)],
        context: ReportPeriodContext
    ) -> [ReportChartBar] {
        let calendar = context.calendar
        return (0..<count).map { i in
            let date = calendar.date(byAdding: .month, value: i, to: context.range.start) ?? context.range.start
            let key = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
            let bucket = buckets[key] ?? (0, 0)
            return ReportChartBar(
                id: "\(i)",
                label: date.formatted(.dateTime.month(.abbreviated)),
                income: bucket.income,
                expense: bucket.expense
            )
        }
    }

    private static func makeSpendingBreakdown(
        categoryTotals: [String: CategoryTotal]
    ) -> [ReportCategoryBreakdown] {
        let sorted = categoryTotals.values.sorted { $0.total > $1.total }.prefix(8)
        let displayedTotal = sorted.reduce(0.0) { $0 + $1.total }
        let palette: [Color] = [.red, .purple, .orange, .blue, .green, .pink, .indigo, .teal]

        return sorted.enumerated().map { index, item in
            ReportCategoryBreakdown(
                id: item.name,
                name: item.name,
                icon: item.icon,
                amount: item.total,
                color: item.color.map { Color(hex: $0) } ?? palette[index % palette.count],
                percentage: displayedTotal > 0 ? item.total / displayedTotal * 100 : 0
            )
        }
    }
}
