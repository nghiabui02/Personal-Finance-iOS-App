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
    let bankFee: Double
    let note: String?
    let occurrenceCount: Int
}

// One-tap chips on the "new transaction" form: groups the last 90 days by
// (type, category, wallet, exact amount) — amounts stay exact on purpose,
// since rounding would merge unrelated habits (a 35k and a 45k coffee) into
// a total that was never actually spent.
@MainActor
enum FrequentTransactionSuggestionCalculator {
    static func calculate(
        transactions: [LocalTransaction],
        categories: [LocalCategory],
        windowDays: Int = 90,
        limit: Int = 5,
        now: Date = Date()
    ) -> [FrequentTransactionSuggestion] {
        let calendar = LedgerDate.calendar
        let today = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -windowDays, to: today) ?? today
        let categoryLookup = Dictionary(
            categories.filter(\.isActiveMembership).map { ($0.serverId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // A reconciliation is a one-off correction, never a habit worth a shortcut.
        let transactions = transactions.operatingOnly(using: categories)

        struct Group {
            let type: String, categoryId: UUID, walletId: UUID?, amount: Double
            var note: String?
            var bankFee = 0.0
            var lastEdit = Date.distantPast
            var count = 0
            var lastDate = Date.distantPast
        }
        var groups: [String: Group] = [:]

        for tx in transactions {
            guard !tx.isTransfer, tx.debtPaymentId == nil, let catId = tx.categoryId else { continue }
            guard categoryLookup[catId] != nil, tx.transactionDate >= cutoff, tx.transactionDate <= today else { continue }
            let k = key(type: tx.type, categoryId: catId, walletId: tx.walletId, amount: tx.amount)

            var g = groups[k] ?? Group(type: tx.type, categoryId: catId, walletId: tx.walletId, amount: tx.amount)
            g.count += 1
            if tx.transactionDate > g.lastDate || (tx.transactionDate == g.lastDate && tx.updatedAt > g.lastEdit) {
                g.lastDate = tx.transactionDate
                g.lastEdit = tx.updatedAt
                g.note = tx.note
                if tx.type == "expense", tx.walletId != nil, let fee = tx.bankFee, fee > 0, fee < tx.amount {
                    g.bankFee = fee
                } else {
                    g.bankFee = 0
                }
            }
            groups[k] = g
        }

        let suggestions: [FrequentTransactionSuggestion] = groups.compactMap { k, g in
            guard g.count >= 2, let cat = categoryLookup[g.categoryId] else { return nil }
            return FrequentTransactionSuggestion(
                id: k, type: g.type, categoryId: g.categoryId, categoryName: cat.displayName,
                categoryIcon: cat.icon ?? "📦", categoryColor: cat.color,
                walletId: g.walletId, amount: g.amount, bankFee: g.bankFee, note: g.note, occurrenceCount: g.count
            )
        }

        return Array(
            suggestions.sorted {
                if $0.occurrenceCount != $1.occurrenceCount { return $0.occurrenceCount > $1.occurrenceCount }
                if $0.amount != $1.amount { return $0.amount > $1.amount }
                return $0.id < $1.id
            }.prefix(limit)
        )
    }

    private static func key(type: String, categoryId: UUID?, walletId: UUID?, amount: Double) -> String {
        "\(type)|\(categoryId?.uuidString ?? "none")|\(walletId?.uuidString ?? "none")|\(amount)"
    }
}
