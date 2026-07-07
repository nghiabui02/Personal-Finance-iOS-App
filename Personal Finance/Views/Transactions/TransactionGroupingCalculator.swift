import Foundation

struct TransactionGroupedData {
    let all: [(Date, [LocalTransaction])]
    let income: [(Date, [LocalTransaction])]
    let expense: [(Date, [LocalTransaction])]
}

enum TransactionGroupingCalculator {
    static func group(
        _ transactions: [LocalTransaction],
        calendar: Calendar = .current
    ) -> TransactionGroupedData {
        var all: [Date: [LocalTransaction]] = [:]
        var income: [Date: [LocalTransaction]] = [:]
        var expense: [Date: [LocalTransaction]] = [:]

        for transaction in transactions {
            let day = calendar.startOfDay(for: transaction.transactionDate)
            all[day, default: []].append(transaction)

            if transaction.type == "income" {
                income[day, default: []].append(transaction)
            } else {
                expense[day, default: []].append(transaction)
            }
        }

        return TransactionGroupedData(
            all: all.sorted { $0.key > $1.key },
            income: income.sorted { $0.key > $1.key },
            expense: expense.sorted { $0.key > $1.key }
        )
    }
}
