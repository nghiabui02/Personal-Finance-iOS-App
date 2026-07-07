import SwiftUI

struct ReportMetrics {
    var income: Double = 0
    var expense: Double = 0
    var currentNetWorth: Double = 0
    var chartData: [ReportChartBar] = []
    var spendingBreakdown: [ReportCategoryBreakdown] = []

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
        let transactionMetrics = calculateTransactionMetrics(
            transactions: transactions,
            context: context
        )

        return ReportMetrics(
            income: transactionMetrics.income,
            expense: transactionMetrics.expense,
            currentNetWorth: calculateCurrentNetWorth(wallets: wallets, debts: debts),
            chartData: makeChartBars(
                buckets: transactionMetrics.buckets,
                context: context
            ),
            spendingBreakdown: makeSpendingBreakdown(
                categoryTotals: transactionMetrics.categoryTotals
            )
        )
    }

    private typealias CategoryTotal = (
        name: String,
        icon: String,
        color: String?,
        total: Double
    )

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

        for transaction in transactions {
            let date = transaction.transactionDate
            guard date >= range.start && date < dayAfterEnd else { continue }
            guard !transaction.isTransfer else { continue }

            let bucketKey = bucketKey(for: date, period: context.period, calendar: calendar)
            if transaction.type == "income" {
                income += transaction.amount
                buckets[bucketKey, default: (0, 0)].income += transaction.amount
            } else {
                expense += transaction.amount
                buckets[bucketKey, default: (0, 0)].expense += transaction.amount
                accumulateExpense(transaction, categoryTotals: &categoryTotals)
            }
        }

        return (income, expense, buckets, categoryTotals)
    }

    private static func bucketKey(
        for date: Date,
        period: ReportPeriod,
        calendar: Calendar
    ) -> Date {
        switch period {
        case .week, .month:
            return calendar.startOfDay(for: date)
        case .quarter, .year:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        }
    }

    private static func accumulateExpense(
        _ transaction: LocalTransaction,
        categoryTotals: inout [String: CategoryTotal]
    ) {
        let key = transaction.categoryId?.uuidString
            ?? transaction.categoryName
            ?? "other"
        let existing = categoryTotals[key]
        categoryTotals[key] = (
            name: existing?.name ?? transaction.categoryName ?? "Other",
            icon: existing?.icon ?? transaction.categoryIcon ?? "💸",
            color: existing?.color ?? transaction.categoryColor,
            total: (existing?.total ?? 0) + transaction.amount
        )
    }

    private static func calculateCurrentNetWorth(
        wallets: [LocalWallet],
        debts: [LocalDebt]
    ) -> Double {
        let cash = wallets.filter { $0.type != "credit" }.reduce(0) { $0 + $1.balance }
        let creditDebt = wallets.filter { $0.type == "credit" }.reduce(0) { $0 + $1.amountOwed }
        let activeDebts = debts.filter { $0.status != "completed" }
        let lent = activeDebts.filter { $0.type == "lend" }.reduce(0) { $0 + $1.remainingAmount }
        let borrowed = activeDebts.filter { $0.type == "borrow" }.reduce(0) { $0 + $1.remainingAmount }
        return cash + lent - creditDebt - borrowed
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
            let dayCount = context.calendar.range(
                of: .day,
                in: .month,
                for: context.referenceDate
            )?.count ?? 0
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
        return (0..<count).map { index in
            let date = calendar.date(byAdding: .day, value: index, to: context.range.start) ?? context.range.start
            let bucket = buckets[calendar.startOfDay(for: date)] ?? (0, 0)
            return ReportChartBar(
                id: "\(index)",
                label: labels[index],
                income: bucket.income,
                expense: bucket.expense
            )
        }
    }

    private static func makeMonthlyBars(
        count: Int,
        buckets: [Date: (income: Double, expense: Double)],
        context: ReportPeriodContext
    ) -> [ReportChartBar] {
        let calendar = context.calendar
        return (0..<count).map { index in
            let date = calendar.date(byAdding: .month, value: index, to: context.range.start) ?? context.range.start
            let bucketKey = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
            let bucket = buckets[bucketKey] ?? (0, 0)
            return ReportChartBar(
                id: "\(index)",
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
