import Foundation

struct BudgetUsage {
    let spent: Double
    let effectiveAmount: Double
}

protocol BudgetHistoryRow {
    var budgetId: UUID { get }
    var budgetMonth: String { get }
    var categoryId: UUID? { get }
    var amount: Double { get }
    var active: Bool { get }
    var rollover: Bool { get }
}

extension LocalBudget: BudgetHistoryRow {
    var budgetId: UUID { serverId }
    var budgetMonth: String { LedgerDate.string(from: month) }
}

extension RemoteBudget: BudgetHistoryRow {
    var budgetId: UUID { id }
    var budgetMonth: String { month }
}

enum BudgetUsageCalculator {
    typealias MonthlySpending = [UUID: [String: Double]]

    static func spending(from operatingTransactions: [LocalTransaction]) -> MonthlySpending {
        var spending: MonthlySpending = [:]
        for row in operatingTransactions where row.type == "expense" {
            guard let categoryId = row.categoryId, let month = LedgerDate.startOfMonth(for: row.transactionDate) else {
                continue
            }
            spending[categoryId, default: [:]][LedgerDate.string(from: month), default: 0] += row.amount
        }
        return spending
    }

    /// The preceding active month's leftover can carry even if that month received no carry itself.
    static func calculate<Row: BudgetHistoryRow>(budgets: [Row], spending: MonthlySpending) -> [UUID: BudgetUsage] {
        var result: [UUID: BudgetUsage] = [:]
        var previous: [UUID: (nextMonth: String, leftover: Double)] = [:]

        for budget in budgets.sorted(by: { $0.budgetMonth < $1.budgetMonth }) {
            guard let categoryId = budget.categoryId else {
                result[budget.budgetId] = BudgetUsage(spent: 0, effectiveAmount: budget.amount)
                continue
            }
            let month = budget.budgetMonth
            let spent = spending[categoryId]?[month] ?? 0
            let prior = previous[categoryId]
            let carry = budget.active && budget.rollover && prior?.nextMonth == month ? prior?.leftover ?? 0 : 0
            let effective = budget.amount + carry
            result[budget.budgetId] = BudgetUsage(spent: spent, effectiveAmount: effective)

            if budget.active, let next = shiftedMonth(month, by: 1) {
                previous[categoryId] = (next, effective - spent)
            }
        }
        return result
    }

    /// Earliest month whose spending feeds the usage of the budgets set for `month`.
    ///
    /// Mirrors the carry rule in `calculate`: a rollover budget takes the leftover of
    /// an active budget in the month right before it, which may carry its own.
    static func historyStart<Row: BudgetHistoryRow>(budgets: [Row], month: String) -> String {
        var activeByCategory: [UUID: [String: Row]] = [:]
        for row in budgets where row.active {
            guard let categoryId = row.categoryId else { continue }
            activeByCategory[categoryId, default: [:]][row.budgetMonth] = row
        }
        var earliest = month
        for row in budgets where row.budgetMonth == month {
            guard let categoryId = row.categoryId else { continue }
            var current = row
            while current.active, current.rollover,
                let previousMonth = shiftedMonth(current.budgetMonth, by: -1),
                let previous = activeByCategory[categoryId]?[previousMonth]
            {
                earliest = min(earliest, previousMonth)
                current = previous
            }
        }
        return earliest
    }

    private static func shiftedMonth(_ month: String, by delta: Int) -> String? {
        guard let date = LedgerDate.date(from: month),
            let shifted = LedgerDate.calendar.date(byAdding: .month, value: delta, to: date)
        else { return nil }
        return LedgerDate.string(from: shifted)
    }

    static func calculate(
        budgets: [LocalBudget], operatingTransactions: [LocalTransaction]
    ) -> [UUID: BudgetUsage] {
        calculate(budgets: budgets, spending: spending(from: operatingTransactions))
    }
}
