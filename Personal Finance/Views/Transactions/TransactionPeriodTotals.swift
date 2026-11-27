import Foundation

typealias DailyTotals = [Date: (income: Decimal, expense: Decimal)]

enum TransactionPeriodTotalsCalculator {
    static func dailyTotals(from operatingTransactions: [LocalTransaction]) -> DailyTotals {
        operatingTransactions.reduce(into: [:]) { totals, transaction in
            let day = LedgerDate.calendar.startOfDay(for: transaction.transactionDate)
            if transaction.type == .income {
                totals[day, default: (0, 0)].income += transaction.amount
            } else {
                totals[day, default: (0, 0)].expense += transaction.amount
            }
        }
    }
}
