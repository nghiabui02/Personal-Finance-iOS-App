import Foundation

struct BudgetSuggestion: Identifiable {
    let id: UUID
    let categoryId: UUID
    let categoryName: String
    let categoryIcon: String
    let categoryColor: String?
    let amount: Decimal
}

// Median (not mean) of the last 3 calendar months' spending per category —
// a single big purchase shouldn't drag the suggested cap up.
@MainActor
enum BudgetSuggestionCalculator {
    static func calculate(
        transactions: [LocalTransaction],
        categories: [LocalCategory],
        existingBudgetCategoryIds: Set<UUID>,
        targetMonth: Date,
        calendar: Calendar = LedgerDate.calendar,
        limit: Int = 5
    ) -> [BudgetSuggestion] {
        guard
            let startOfTarget = calendar.date(from: calendar.dateComponents([.year, .month], from: targetMonth)),
            let startWindow = calendar.date(byAdding: .month, value: -3, to: startOfTarget)
        else { return [] }

        let categoryLookup = Dictionary(categories.map { ($0.serverId, $0) }, uniquingKeysWith: { first, _ in first })
        let operating = transactions.operatingOnly(using: categories)

        var monthlyTotals: [UUID: [String: Decimal]] = [:]
        for tx in operating {
            guard tx.type == .expense, let catId = tx.categoryId else { continue }
            guard tx.transactionDate >= startWindow, tx.transactionDate < startOfTarget else { continue }
            guard !existingBudgetCategoryIds.contains(catId) else { continue }
            let key = LedgerDate.monthKey(for: tx.transactionDate)
            monthlyTotals[catId, default: [:]][key, default: 0] += tx.amount
        }

        let suggestions = monthlyTotals.compactMap { catId, monthTotals -> BudgetSuggestion? in
            guard let cat = categoryLookup[catId], cat.isActiveMembership else { return nil }
            let amount = max(50_000, roundedToStep(median(Array(monthTotals.values)), step: 50_000))
            return BudgetSuggestion(
                id: catId, categoryId: catId, categoryName: cat.displayName,
                categoryIcon: cat.icon ?? "📦", categoryColor: cat.color, amount: amount
            )
        }

        return Array(suggestions.sorted { $0.amount > $1.amount }.prefix(limit))
    }

    /// Nearest multiple of `step`, halves rounding up.
    private static func roundedToStep(_ value: Decimal, step: Decimal) -> Decimal {
        var quotient = value / step
        var rounded = Decimal()
        NSDecimalRound(&rounded, &quotient, 0, .plain)
        return rounded * step
    }

    private static func median(_ values: [Decimal]) -> Decimal {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
