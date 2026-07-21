import SwiftUI

struct DashboardMetrics {
    var income: Double = 0
    var expense: Double = 0
    var netWorth: Double = 0
    var cash: Double = 0
    var outstandingLent: Double = 0
    var outstandingBorrowed: Double = 0
    var recentTransactions: [LocalTransaction] = []
    var spendingByCategoryId: [UUID: Double] = [:]
    var spendingItems: [CategorySpending] = []
    var currentBudgets: [LocalBudget] = []
    var alerts: [DashboardAlert] = []

    var netBalance: Double { income - expense }
}

enum DashboardMetricsCalculator {
    static func calculate(
        transactions: [LocalTransaction],
        wallets: [LocalWallet],
        budgets: [LocalBudget],
        debts: [LocalDebt],
        selectedMonth: Date,
        currency: String,
        calendar: Calendar = .current
    ) -> DashboardMetrics {
        let transactionData = calculateTransactions(
            transactions,
            selectedMonth: selectedMonth,
            calendar: calendar
        )
        let currentBudgets = budgets.filter {
            calendar.isDate($0.month, equalTo: selectedMonth, toGranularity: .month)
        }
        let debtTotals = calculateDebtTotals(debts)
        let cash = wallets.filter { $0.type != "credit" }.reduce(0) { $0 + $1.balance }
        let creditDebt = wallets.filter { $0.type == "credit" }.reduce(0) { $0 + $1.amountOwed }

        return DashboardMetrics(
            income: transactionData.income,
            expense: transactionData.expense,
            netWorth: cash + debtTotals.lent - creditDebt - debtTotals.borrowed,
            cash: cash,
            outstandingLent: debtTotals.lent,
            outstandingBorrowed: debtTotals.borrowed,
            recentTransactions: transactionData.recent,
            spendingByCategoryId: transactionData.spendingByCategoryId,
            spendingItems: makeSpendingItems(from: transactionData.categoryTotals),
            currentBudgets: currentBudgets,
            alerts: makeAlerts(
                budgets: currentBudgets,
                spending: transactionData.spendingByCategoryId,
                debts: debts,
                currency: currency,
                calendar: calendar
            )
        )
    }

    private typealias CategoryTotal = (
        name: String,
        icon: String,
        color: String?,
        total: Double
    )

    private static func calculateTransactions(
        _ transactions: [LocalTransaction],
        selectedMonth: Date,
        calendar: Calendar
    ) -> (
        income: Double,
        expense: Double,
        recent: [LocalTransaction],
        spendingByCategoryId: [UUID: Double],
        categoryTotals: [String: CategoryTotal]
    ) {
        var income = 0.0
        var expense = 0.0
        var recent: [LocalTransaction] = []
        var spending: [UUID: Double] = [:]
        var categories: [String: CategoryTotal] = [:]

        for transaction in transactions {
            guard calendar.isDate(
                transaction.transactionDate,
                equalTo: selectedMonth,
                toGranularity: .month
            ) else { continue }

            if !transaction.isTransfer {
                if transaction.type == "income" {
                    income += transaction.amount
                } else {
                    expense += transaction.amount
                    accumulateExpense(
                        transaction,
                        categoryTotals: &categories,
                        spendingByCategoryId: &spending
                    )
                }
            }

            if recent.count < 6 {
                recent.append(transaction)
            }
        }

        return (income, expense, recent, spending, categories)
    }

    private static func accumulateExpense(
        _ transaction: LocalTransaction,
        categoryTotals: inout [String: CategoryTotal],
        spendingByCategoryId: inout [UUID: Double]
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
        if let categoryId = transaction.categoryId {
            spendingByCategoryId[categoryId, default: 0] += transaction.amount
        }
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
                percentage: displayedTotal > 0 ? item.total / displayedTotal * 100 : 0
            )
        }
    }

    private static func calculateDebtTotals(
        _ debts: [LocalDebt]
    ) -> (lent: Double, borrowed: Double) {
        let active = debts.filter { $0.status != "completed" }
        let lent = active.filter { $0.type == "lend" }.reduce(0) { $0 + $1.remainingAmount }
        let borrowed = active.filter { $0.type == "borrow" }.reduce(0) { $0 + $1.remainingAmount }
        return (lent, borrowed)
    }

    private static func makeAlerts(
        budgets: [LocalBudget],
        spending: [UUID: Double],
        debts: [LocalDebt],
        currency: String,
        calendar: Calendar
    ) -> [DashboardAlert] {
        var alerts = makeBudgetAlerts(
            budgets: budgets,
            spending: spending,
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
        spending: [UUID: Double],
        currency: String
    ) -> [DashboardAlert] {
        budgets.compactMap { budget in
            let spent = budget.categoryId.map { spending[$0, default: 0] } ?? 0
            guard budget.amount > 0, spent >= budget.amount * 0.8 else { return nil }
            let exceeded = spent > budget.amount
            return DashboardAlert(
                id: "budget-\(budget.serverId)",
                title: exceeded ? "Budget exceeded" : "Budget almost used",
                message: "\(budget.categoryName): \(spent.formatted(currency: currency)) of \(budget.amount.formatted(currency: currency))",
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
            guard debt.status != "completed", let dueDate = debt.dueDate else { return nil }
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
