import Foundation

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
}
