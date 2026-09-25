import Foundation

/// Every date in this app is a *ledger* date, not a device-local one.
///
/// `transaction_date`, `month`, `next_run_date` etc. are plain DATE strings on the
/// server, decided once in Asia/Ho_Chi_Minh. Formatting or comparing them against the
/// device's timezone makes the same data read differently abroad — and differently from
/// the web client. Route all of it through here instead of redeclaring a formatter.
enum LedgerDate {
    static let timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh") ?? .current

    /// "yyyy-MM-dd" — the wire format for every DATE column.
    static let dayFormatter: DateFormatter = formatter("yyyy-MM-dd")

    /// "yyyy-MM" — month bucket key for grouping.
    static let monthFormatter: DateFormatter = formatter("yyyy-MM")

    /// Calendar pinned to the ledger timezone, for "today" and component math.
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }()

    static func string(from date: Date) -> String { dayFormatter.string(from: date) }
    static func date(from string: String) -> Date? { dayFormatter.date(from: string) }
    static func monthKey(for date: Date) -> String { monthFormatter.string(from: date) }

    /// Start of the calendar month containing `date`, in ledger time.
    static func startOfMonth(for date: Date) -> Date? {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        return f
    }
}
