import Foundation

enum TransactionDateRange {
    static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        return formatter
    }()

    static func monthStart(
        for date: Date,
        calendar: Calendar = .current
    ) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    static func monthRange(
        for date: Date,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date)? {
        let start = monthStart(for: date, calendar: calendar)
        guard let end = calendar.date(byAdding: .month, value: 1, to: start) else {
            return nil
        }
        return (start, end)
    }

    static func monthRangeStrings(
        for date: Date,
        calendar: Calendar = .current
    ) -> (start: String, end: String) {
        guard let range = monthRange(for: date, calendar: calendar) else {
            let fallback = apiDateString(from: date)
            return (fallback, fallback)
        }
        return (apiDateString(from: range.start), apiDateString(from: range.end))
    }

    static func apiDateString(from date: Date) -> String {
        apiDateFormatter.string(from: date)
    }

    static func apiDate(from string: String) -> Date? {
        apiDateFormatter.date(from: string)
    }
}
