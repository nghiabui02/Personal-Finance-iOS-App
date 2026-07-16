import Foundation

enum TransactionTypeFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case expense = "Expense"
    case income = "Income"

    var id: Self { self }

    var transactionType: String? {
        switch self {
        case .all: nil
        case .expense: "expense"
        case .income: "income"
        }
    }
}

enum TransactionPeriodFilter: String, CaseIterable, Identifiable {
    case month = "Month"
    case week = "Week"
    case day = "Day"

    var id: Self { self }
}

struct TransactionFilterState: Equatable {
    var type: TransactionTypeFilter = .all
    var period: TransactionPeriodFilter = .day
    var categoryId: UUID?
    var keyword = ""

    var hasContentFilter: Bool {
        type != .all || categoryId != nil || !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum TransactionFilterEngine {
    static func apply(
        _ filter: TransactionFilterState,
        to transactions: [LocalTransaction],
        selectedMonth: Date,
        selectedDate: Date?,
        calendar: Calendar = .current
    ) -> [LocalTransaction] {
        guard let interval = dateInterval(
            for: filter.period,
            selectedMonth: selectedMonth,
            selectedDate: selectedDate,
            calendar: calendar
        ) else {
            return []
        }

        let keyword = normalized(filter.keyword)

        return transactions.filter { transaction in
            contains(transaction.transactionDate, in: interval)
                && matchesType(transaction, filter: filter.type)
                && matchesCategory(transaction, categoryId: filter.categoryId)
                && matchesKeyword(transaction, keyword: keyword)
        }
    }

    static func dateInterval(
        for period: TransactionPeriodFilter,
        selectedMonth: Date,
        selectedDate: Date?,
        calendar: Calendar = .current
    ) -> DateInterval? {
        switch period {
        case .month:
            guard let range = TransactionDateRange.monthRange(for: selectedMonth, calendar: calendar) else {
                return nil
            }
            return DateInterval(start: range.start, end: range.end)

        case .week:
            var mondayCalendar = calendar
            mondayCalendar.firstWeekday = 2
            let anchor = selectedDate ?? defaultAnchor(for: selectedMonth, calendar: calendar)
            guard let week = mondayCalendar.dateInterval(of: .weekOfYear, for: anchor),
                  let month = TransactionDateRange.monthRange(for: selectedMonth, calendar: calendar) else {
                return nil
            }
            let start = max(week.start, month.start)
            let end = min(week.end, month.end)
            return start < end ? DateInterval(start: start, end: end) : nil

        case .day:
            let anchor = selectedDate ?? defaultAnchor(for: selectedMonth, calendar: calendar)
            let start = calendar.startOfDay(for: anchor)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return DateInterval(start: start, end: end)
        }
    }

    static func defaultAnchor(for selectedMonth: Date, calendar: Calendar = .current) -> Date {
        calendar.isDate(selectedMonth, equalTo: Date(), toGranularity: .month)
            ? Date()
            : TransactionDateRange.monthStart(for: selectedMonth, calendar: calendar)
    }

    private static func matchesType(
        _ transaction: LocalTransaction,
        filter: TransactionTypeFilter
    ) -> Bool {
        guard let type = filter.transactionType else { return true }
        return transaction.type == type
    }

    private static func contains(_ date: Date, in interval: DateInterval) -> Bool {
        date >= interval.start && date < interval.end
    }

    private static func matchesCategory(
        _ transaction: LocalTransaction,
        categoryId: UUID?
    ) -> Bool {
        guard let categoryId else { return true }
        return transaction.categoryId == categoryId
    }

    private static func matchesKeyword(
        _ transaction: LocalTransaction,
        keyword: String
    ) -> Bool {
        guard !keyword.isEmpty else { return true }
        return [transaction.note, transaction.categoryName, transaction.walletName]
            .compactMap { $0 }
            .contains { normalized($0).contains(keyword) }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
