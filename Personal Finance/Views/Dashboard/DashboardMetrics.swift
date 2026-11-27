import SwiftUI

struct DashboardMetrics {
    var income: Decimal = 0
    var expense: Decimal = 0
    var netWorth: Decimal = 0
    var cash: Decimal = 0
    var outstandingLent: Decimal = 0
    var outstandingBorrowed: Decimal = 0
    var recentTransactions: [LocalTransaction] = []
    var spendingItems: [CategorySpending] = []
    var budgetUsage: [UUID: BudgetUsage] = [:]
    var currentBudgets: [LocalBudget] = []
    var alerts: [DashboardAlert] = []
    var spendingPaceDeltaPct: Double? = nil

    var netBalance: Decimal { income - expense }
}

@MainActor
enum DashboardMetricsCalculator {
    static func calculate(
        transactions: [LocalTransaction],
        categories: [LocalCategory],
        wallets: [LocalWallet],
        budgets: [LocalBudget],
        debts: [LocalDebt],
        selectedMonth: Date,
        currency: String,
        calendar: Calendar = LedgerDate.calendar
    ) -> DashboardMetrics {
        let operating = transactions.operatingOnly(using: categories)
        let transactionData = calculateTransactions(
            operating,
            selectedMonth: selectedMonth,
            calendar: calendar
        )
        let currentBudgets = budgets.filter {
            $0.active && calendar.isDate($0.month, equalTo: selectedMonth, toGranularity: .month)
        }
        let netWorth = NetWorth.calculate(wallets: wallets, debts: debts)
        let budgetUsage = BudgetUsageCalculator.calculate(budgets: budgets, operatingTransactions: operating)

        return DashboardMetrics(
            income: transactionData.income,
            expense: transactionData.expense,
            netWorth: netWorth.total,
            cash: netWorth.cash,
            outstandingLent: netWorth.lent,
            outstandingBorrowed: netWorth.borrowed,
            recentTransactions: Array(transactions.lazy.filter {
                calendar.isDate($0.transactionDate, equalTo: selectedMonth, toGranularity: .month)
            }.prefix(6)),
            spendingItems: makeSpendingItems(from: transactionData.categoryTotals),
            budgetUsage: budgetUsage,
            currentBudgets: currentBudgets,
            alerts: makeAlerts(
                budgets: currentBudgets,
                usage: budgetUsage,
                debts: debts,
                currency: currency,
                calendar: calendar
            ),
            spendingPaceDeltaPct: calculateSpendingPace(
                transactions: operating,
                selectedMonth: selectedMonth,
                actualExpense: transactionData.expense
            )
        )
    }

    // Compares this month's expense so far against the last 3 months' average,
    // prorated by days elapsed — an unfinished month would otherwise always
    // look "under budget".
    private static func calculateSpendingPace(
        transactions: [LocalTransaction],
        selectedMonth: Date,
        actualExpense: Decimal
    ) -> Double? {
        // "Today" must follow ledger time, not the device's — otherwise pace reads
        // differently on iOS than web for the same data when traveling.
        let ledgerCalendar = LedgerDate.calendar

        guard
            let startOfTarget = LedgerDate.startOfMonth(for: selectedMonth),
            let startWindow = ledgerCalendar.date(byAdding: .month, value: -3, to: startOfTarget)
        else { return nil }

        var byMonth: [String: Decimal] = [:]
        for tx in transactions where tx.type == .expense && !tx.isTransfer {
            guard tx.transactionDate >= startWindow, tx.transactionDate < startOfTarget else { continue }
            byMonth[LedgerDate.monthKey(for: tx.transactionDate), default: 0] += tx.amount
        }
        guard !byMonth.isEmpty else { return nil }
        let monthlyAverage = byMonth.values.reduce(0, +) / Decimal(byMonth.count)
        guard monthlyAverage > 0 else { return nil }

        let today = ledgerCalendar.startOfDay(for: Date())
        let daysInMonth = ledgerCalendar.range(of: .day, in: .month, for: startOfTarget)?.count ?? 30
        let daysElapsed: Int
        if ledgerCalendar.isDate(today, equalTo: startOfTarget, toGranularity: .month) {
            daysElapsed = ledgerCalendar.component(.day, from: today)
        } else if today > startOfTarget {
            daysElapsed = daysInMonth
        } else {
            daysElapsed = 0
        }
        guard daysElapsed > 0 else { return nil }

        let expected = monthlyAverage * Decimal(daysElapsed) / Decimal(daysInMonth)
        guard expected > 0 else { return nil }
        return (actualExpense / expected).doubleValue - 1
    }

    private typealias CategoryTotal = (
        name: String,
        icon: String,
        color: String?,
        total: Decimal
    )

    private static func calculateTransactions(
        _ transactions: [LocalTransaction],
        selectedMonth: Date,
        calendar: Calendar
    ) -> (
        income: Decimal,
        expense: Decimal,
        categoryTotals: [String: CategoryTotal]
    ) {
        var income: Decimal = 0
        var expense: Decimal = 0
        var categories: [String: CategoryTotal] = [:]

        for transaction in transactions {
            guard calendar.isDate(
                transaction.transactionDate,
                equalTo: selectedMonth,
                toGranularity: .month
            ) else { continue }

            if transaction.type == .income {
                income += transaction.amount
            } else {
                expense += transaction.amount
                accumulateExpense(transaction, categoryTotals: &categories)
            }
        }

        return (income, expense, categories)
    }

    private static func accumulateExpense(
        _ transaction: LocalTransaction,
        categoryTotals: inout [String: CategoryTotal]
    ) {
        let key = transaction.categoryId?.uuidString
            ?? transaction.categoryLabel
            ?? "other"
        let existing = categoryTotals[key]
        categoryTotals[key] = (
            name: existing?.name ?? transaction.categoryLabel ?? AppLocalization.shared.language.text("Other"),
            icon: existing?.icon ?? transaction.categoryIcon ?? "💸",
            color: existing?.color ?? transaction.categoryColor,
            total: (existing?.total ?? 0) + transaction.amount
        )
    }

    private static func makeSpendingItems(
        from categoryTotals: [String: CategoryTotal]
    ) -> [CategorySpending] {
        let topCategories = categoryTotals.values.sorted { $0.total > $1.total }.prefix(5)
        let displayedTotal = topCategories.reduce(0) { $0 + $1.total }
        let palette: [Color] = [.blue, .indigo, .purple, .pink, .orange]

        return topCategories.enumerated().map { index, item in
            CategorySpending(
                id: item.name,
                name: item.name,
                icon: item.icon,
                color: item.color.map { Color(hex: $0) } ?? palette[index % palette.count],
                amount: item.total,
                percentage: displayedTotal > 0 ? (item.total / displayedTotal * 100).doubleValue : 0
            )
        }
    }

    private static func makeAlerts(
        budgets: [LocalBudget],
        usage: [UUID: BudgetUsage],
        debts: [LocalDebt],
        currency: String,
        calendar: Calendar
    ) -> [DashboardAlert] {
        var alerts = makeBudgetAlerts(
            budgets: budgets,
            usage: usage,
            currency: currency
        )
        alerts.append(contentsOf: makeDebtAlerts(
            debts: debts,
            currency: currency,
            calendar: calendar
        ))
        return Array(alerts.sorted { $0.priority < $1.priority }.prefix(5))
    }

    private static func makeBudgetAlerts(
        budgets: [LocalBudget],
        usage: [UUID: BudgetUsage],
        currency: String
    ) -> [DashboardAlert] {
        budgets.compactMap { budget in
            guard let budgetUsage = usage[budget.serverId] else { return nil }
            let spent = budgetUsage.spent
            let limit = budgetUsage.effectiveAmount
            let exceeded = spent > limit
            guard exceeded || (limit > 0 && spent / limit >= 0.8) else { return nil }
            return DashboardAlert(
                id: "budget-\(budget.serverId)",
                title: exceeded ? "Budget exceeded" : "Budget almost used",
                message: AppLocalization.shared.language.text("%@: %@ of %@", budget.categoryLabel, spent.formatted(currency: currency), limit.formatted(currency: currency)),
                symbol: exceeded ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill",
                color: exceeded ? .red : .orange,
                priority: exceeded ? 0 : 2
            )
        }
    }

    private static func makeDebtAlerts(
        debts: [LocalDebt],
        currency: String,
        calendar: Calendar
    ) -> [DashboardAlert] {
        let today = calendar.startOfDay(for: Date())
        guard let sevenDaysFromNow = calendar.date(byAdding: .day, value: 7, to: today) else {
            return []
        }

        return debts.compactMap { debt in
            guard debt.status != .completed, let dueDate = debt.dueDate else { return nil }
            let dueDay = calendar.startOfDay(for: dueDate)
            guard dueDay <= sevenDaysFromNow else { return nil }
            let overdue = dueDay < today
            return DashboardAlert(
                id: "debt-\(debt.serverId)",
                title: overdue ? "Debt overdue" : "Debt due soon",
                message: "\(debt.personName) · \(debt.remainingAmount.formatted(currency: currency))",
                symbol: overdue ? "calendar.badge.exclamationmark" : "calendar.badge.clock",
                color: overdue ? .red : .orange,
                priority: overdue ? 1 : 3
            )
        }
    }
}
