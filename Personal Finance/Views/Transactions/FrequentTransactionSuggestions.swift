import Foundation

struct FrequentTransactionSuggestion: Identifiable {
    let id: String
    let type: String
    let categoryId: UUID
    let categoryName: String
    let categoryIcon: String
    let categoryColor: String?
    let walletId: UUID?
    let amount: Double
    let note: String?
    let occurrenceCount: Int
}

// One-tap chips on the "new transaction" form: groups the last 90 days by
// (type, category, wallet, exact amount) — amounts stay exact on purpose,
// since rounding would merge unrelated habits (a 35k and a 45k coffee) into
// a total that was never actually spent.
enum FrequentTransactionSuggestionCalculator {
    static func calculate(
        transactions: [LocalTransaction],
        categories: [LocalCategory],
        windowDays: Int = 90,
        limit: Int = 5,
        now: Date = Date()
    ) -> [FrequentTransactionSuggestion] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -windowDays, to: now) ?? now
        let categoryLookup = Dictionary(uniqueKeysWithValues: categories.map { ($0.serverId, $0) })
        // A reconciliation is a one-off correction, never a habit worth a shortcut.
        let transactions = transactions.excludingAdjustments(using: categories)

        struct Group {
            let type: String, categoryId: UUID, walletId: UUID?, amount: Double
            var note: String?
            var count = 0
            var lastDate = Date.distantPast
        }
        var groups: [String: Group] = [:]

        for tx in transactions {
            guard !tx.isTransfer, tx.debtPaymentId == nil, let catId = tx.categoryId else { continue }
            guard tx.transactionDate >= cutoff else { continue }
            let k = key(type: tx.type, categoryId: catId, walletId: tx.walletId, amount: tx.amount)

            var g = groups[k] ?? Group(type: tx.type, categoryId: catId, walletId: tx.walletId, amount: tx.amount)
            g.count += 1
            if tx.transactionDate > g.lastDate { g.lastDate = tx.transactionDate; g.note = tx.note }
            groups[k] = g
        }

        let suggestions: [FrequentTransactionSuggestion] = groups.compactMap { k, g in
            guard g.count >= 2, let cat = categoryLookup[g.categoryId] else { return nil }
            return FrequentTransactionSuggestion(
                id: k, type: g.type, categoryId: g.categoryId, categoryName: cat.name,
                categoryIcon: cat.icon ?? "📦", categoryColor: cat.color,
                walletId: g.walletId, amount: g.amount, note: g.note, occurrenceCount: g.count
            )
        }

        return Array(
            suggestions.sorted {
                $0.occurrenceCount != $1.occurrenceCount
                    ? $0.occurrenceCount > $1.occurrenceCount
                    : $0.amount > $1.amount
            }.prefix(limit)
        )
    }

    private static func key(type: String, categoryId: UUID?, walletId: UUID?, amount: Double) -> String {
        "\(type)|\(categoryId?.uuidString ?? "none")|\(walletId?.uuidString ?? "none")|\(amount)"
    }
}
