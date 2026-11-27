import SwiftData
import SwiftUI

enum TransactionDateRange {
    static func monthStart(
        for date: Date,
        calendar: Calendar = LedgerDate.calendar
    ) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    static func monthRange(
        for date: Date,
        calendar: Calendar = LedgerDate.calendar
    ) -> (start: Date, end: Date)? {
        let start = monthStart(for: date, calendar: calendar)
        guard let end = calendar.date(byAdding: .month, value: 1, to: start) else {
            return nil
        }
        return (start, end)
    }

    /// `monthsBefore` whole months ahead of `month`, through the end of `month`.
    static func window(endingWith month: Date, monthsBefore: Int) -> Range<Date> {
        let calendar = LedgerDate.calendar
        let start = monthStart(for: month)
        let lower = calendar.date(byAdding: .month, value: -monthsBefore, to: start) ?? .distantPast
        let upper = calendar.date(byAdding: .month, value: 1, to: start) ?? .distantFuture
        return lower..<upper
    }

    /// Widens `range` back to the oldest month the rollover budgets of `budgetMonth`
    /// carry from, so a screen that loads only its own dates reports the same usage.
    static func including(
        budgetHistoryOf budgets: [LocalBudget], for budgetMonth: Date, in range: Range<Date>
    ) -> Range<Date> {
        let month = LedgerDate.string(from: monthStart(for: budgetMonth))
        let earliest = BudgetUsageCalculator.historyStart(budgets: budgets, month: month)
        guard let start = LedgerDate.date(from: earliest), start < range.lowerBound else { return range }
        return start..<range.upperBound
    }
}

/// Loads only the transactions dated inside `range`, newest first.
///
/// `@Query` takes a dynamic predicate only in `init`, so a screen whose dates change
/// wraps its content in this rather than holding every transaction ever recorded.
struct TransactionsInRange<Content: View>: View {
    @Query private var transactions: [LocalTransaction]
    private let content: ([LocalTransaction]) -> Content

    init(_ range: Range<Date>, @ViewBuilder content: @escaping ([LocalTransaction]) -> Content) {
        let start = range.lowerBound
        let end = range.upperBound
        _transactions = Query(
            filter: #Predicate { $0.transactionDate >= start && $0.transactionDate < end },
            sort: [
                SortDescriptor(\LocalTransaction.transactionDate, order: .reverse),
                SortDescriptor(\LocalTransaction.updatedAt, order: .reverse)
            ]
        )
        self.content = content
    }

    var body: some View {
        content(transactions)
    }
}
