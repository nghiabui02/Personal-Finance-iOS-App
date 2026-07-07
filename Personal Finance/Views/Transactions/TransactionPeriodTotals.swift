import Foundation

struct TransactionTotalRecord: Decodable {
    let type: String
    let amount: Double
    let transaction_date: String
    let transfer_pair_id: UUID?
}

struct TransactionPeriodTotals {
    var income: Double = 0
    var expense: Double = 0
    var dailyData: [Date: (income: Double, expense: Double)] = [:]
}

enum TransactionPeriodTotalsCalculator {
    static func calculate(
        from records: [TransactionTotalRecord],
        calendar: Calendar = .current
    ) -> TransactionPeriodTotals {
        var totals = TransactionPeriodTotals()

        for record in records {
            guard record.transfer_pair_id == nil else { continue }
            accumulate(
                type: record.type,
                amount: record.amount,
                date: TransactionDateRange.apiDate(from: record.transaction_date),
                totals: &totals,
                calendar: calendar
            )
        }

        return totals
    }

    static func calculate(
        from transactions: [LocalTransaction],
        calendar: Calendar = .current
    ) -> TransactionPeriodTotals {
        var totals = TransactionPeriodTotals()

        for transaction in transactions where !transaction.isTransfer {
            accumulate(
                type: transaction.type,
                amount: transaction.amount,
                date: transaction.transactionDate,
                totals: &totals,
                calendar: calendar
            )
        }

        return totals
    }

    private static func accumulate(
        type: String,
        amount: Double,
        date: Date?,
        totals: inout TransactionPeriodTotals,
        calendar: Calendar
    ) {
        if type == "income" {
            totals.income += amount
        } else {
            totals.expense += amount
        }

        guard let date else { return }
        let day = calendar.startOfDay(for: date)
        var daily = totals.dailyData[day] ?? (0, 0)
        if type == "income" {
            daily.income += amount
        } else {
            daily.expense += amount
        }
        totals.dailyData[day] = daily
    }
}
