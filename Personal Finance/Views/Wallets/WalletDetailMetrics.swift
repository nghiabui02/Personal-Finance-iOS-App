import Foundation

struct WalletDetailMetrics {
    var transactions: [LocalTransaction] = []
    var monthlyIncome: Double = 0
    var monthlyExpense: Double = 0
}

enum WalletDetailMetricsCalculator {
    static func calculate(
        transactions: [LocalTransaction],
        walletId: UUID,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
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
            transactions: walletTransactions,
            monthlyIncome: total(for: "income", in: reportableThisMonth),
            monthlyExpense: total(for: "expense", in: reportableThisMonth)
        )
    }

    private static func total(
        for type: String,
        in transactions: [LocalTransaction]
    ) -> Double {
        transactions
            .filter { $0.type == type }
            .reduce(0) { $0 + $1.amount }
    }
}
