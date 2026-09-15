import Foundation

struct BudgetSuggestion: Identifiable {
    let id: UUID
    let categoryId: UUID
    let categoryName: String
    let categoryIcon: String
    let categoryColor: String?
    let amount: Double
}

// Median (not mean) of the last 3 calendar months' spending per category —
// a single big purchase shouldn't drag the suggested cap up.
enum BudgetSuggestionCalculator {
    private static let monthKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        return f
    }()

    static func calculate(
        transactions: [LocalTransaction],
        categories: [LocalCategory],
        existingBudgetCategoryIds: Set<UUID>,
        targetMonth: Date,
        calendar: Calendar = .current,
        limit: Int = 5
    ) -> [BudgetSuggestion] {
        guard
            let startOfTarget = calendar.date(from: calendar.dateComponents([.year, .month], from: targetMonth)),
            let startWindow = calendar.date(byAdding: .month, value: -3, to: startOfTarget)
        else { return [] }

        let systemCategoryIds = Set(categories.filter { $0.systemKey != nil }.map(\.serverId))
        let categoryLookup = Dictionary(uniqueKeysWithValues: categories.map { ($0.serverId, $0) })

        var monthlyTotals: [UUID: [String: Double]] = [:]
        for tx in transactions {
            guard tx.type == "expense", !tx.isTransfer, let catId = tx.categoryId else { continue }
            guard tx.transactionDate >= startWindow, tx.transactionDate < startOfTarget else { continue }
            guard !systemCategoryIds.contains(catId), !existingBudgetCategoryIds.contains(catId) else { continue }
            let key = monthKeyFormatter.string(from: tx.transactionDate)
            monthlyTotals[catId, default: [:]][key, default: 0] += tx.amount
        }

        let suggestions = monthlyTotals.compactMap { catId, monthTotals -> BudgetSuggestion? in
            guard let cat = categoryLookup[catId] else { return nil }
            let amount = max(50_000, (median(Array(monthTotals.values)) / 50_000).rounded() * 50_000)
            return BudgetSuggestion(
                id: catId, categoryId: catId, categoryName: cat.name,
                categoryIcon: cat.icon ?? "📦", categoryColor: cat.color, amount: amount
            )
        }

        return Array(suggestions.sorted { $0.amount > $1.amount }.prefix(limit))
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
