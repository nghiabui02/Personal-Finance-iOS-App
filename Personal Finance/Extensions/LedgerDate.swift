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

    static func format(_ style: Date.FormatStyle) -> Date.FormatStyle {
        var style = style
        style.calendar = calendar
        style.timeZone = timeZone
        return style
    }

    @MainActor
    static func display(_ style: Date.FormatStyle) -> Date.FormatStyle {
        format(style).locale(AppLocalization.shared.language.locale)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        return f
    }
}

/// A `DATE` column as it travels: the "yyyy-MM-dd" wire string, which the app compares
/// and keys on directly, plus the parsed ledger day.
///
/// Decoding throws on anything that is not a valid day, so a malformed date fails the
/// sync with a decoding error instead of quietly becoming "today" in every report.
struct LedgerDay: Codable, Hashable, Comparable, Sendable {
    let string: String
    let date: Date

    init?(_ string: String) {
        guard let date = LedgerDate.date(from: string) else { return nil }
        self.string = string
        self.date = date
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let day = LedgerDay(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected a yyyy-MM-dd ledger date, got \"\(raw)\".")
        }
        self = day
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.string < rhs.string }
}
