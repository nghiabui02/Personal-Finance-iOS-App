import Foundation

struct WalletDetailMetrics {
    var monthlyIncome: Decimal = 0
    var monthlyExpense: Decimal = 0
}

enum WalletDetailMetricsCalculator {
    static func calculate(
        transactions: [LocalTransaction],
        walletId: UUID,
        referenceDate: Date = Date(),
        calendar: Calendar = LedgerDate.calendar
    ) -> WalletDetailMetrics {
        let walletTransactions = transactions.filter { $0.walletId == walletId }
        let reportableThisMonth = walletTransactions.filter {
            !$0.isTransfer
            && calendar.isDate(
                $0.transactionDate,
                equalTo: referenceDate,
                toGranularity: .month
            )
        }

        return WalletDetailMetrics(
            monthlyIncome: total(for: .income, in: reportableThisMonth),
            monthlyExpense: total(for: .expense, in: reportableThisMonth)
        )
    }

    private static func total(
        for type: TransactionKind,
        in transactions: [LocalTransaction]
    ) -> Decimal {
        transactions
            .filter { $0.type == type }
            .reduce(0) { $0 + $1.amount }
    }
}
