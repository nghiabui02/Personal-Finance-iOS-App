import Foundation

// Money is `Decimal` end to end — the database column is `numeric`, and a binary
// `Double` cannot hold most decimal fractions exactly, so sums and fees drift.

private let vietnameseLocale = Locale(identifier: "vi_VN")
private let vndStyle = Decimal.FormatStyle.Currency(code: "VND", locale: vietnameseLocale)
    .precision(.fractionLength(0))
private let groupedDigitsStyle = Decimal.FormatStyle(locale: vietnameseLocale)
    .precision(.fractionLength(0))

extension Decimal {
    /// For ratios, chart scales and other non-money math. Never feed the result back
    /// into an amount.
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }

    func formatted(currency: String) -> String {
        if currency == "VND" {
            return formatted(vndStyle)
        }
        return formatted(.currency(code: currency))
    }

    func formattedDecimal() -> String {
        guard self > 0 else { return "" }
        return formatted(groupedDigitsStyle)
    }
}

/// Upper bound shared by every currency field: 999.999.999.999 ₫
let maxAmountDigits = 12

/// Keeps the field text and the stored amount in lockstep. Input that is not a plain
/// non-negative amount within `maxAmountDigits` (a pasted minus sign, letters, too many
/// digits) is rejected and the text snaps back to the last accepted amount, so the form
/// can never save a number other than the one on screen.
///
/// `old` is the text before this edit. New input that ends in a separator and one or two
/// digits is a fraction, not a thousands group: a pasted "1,500,000.00" means 1.500.000 ₫,
/// and stripping the separator would store 150.000.000 ₫. Đồng has no minor unit, so the
/// fraction is dropped. A backspace on "12.345" also leaves "12.34", which is why deletions
/// are left alone.
func applyAmountFormat(old: String = "", new: String, amountText: inout String, amount: inout Decimal) {
    let input = isDeletion(from: old, to: new)
        ? new
        : new.replacingOccurrences(of: #"[.,][0-9]{1,2}$"#, with: "", options: .regularExpression)
    if let parsed = parseAmountInput(input) {
        amount = parsed
    }
    amountText = amount.formattedDecimal()
}

/// True when `new` is `old` with characters removed (backspace, cut) rather than new input.
private func isDeletion(from old: String, to new: String) -> Bool {
    guard new.count < old.count else { return false }
    var rest = Substring(old)
    for character in new {
        guard let index = rest.firstIndex(of: character) else { return false }
        rest = rest[rest.index(after: index)...]
    }
    return true
}

/// 0 for an empty field, nil for input that is not a valid amount.
func parseAmountInput(_ text: String) -> Decimal? {
    let groupingSeparators: Set<Character> = [".", ",", " ", "\u{00A0}"]
    let digits = text.filter { !groupingSeparators.contains($0) }
    guard !digits.isEmpty else { return 0 }
    guard digits.count <= maxAmountDigits,
          digits.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
    return Decimal(string: digits)
}

/// Same digits shifted up one power of ten at a time: "5" suggests 5.000 / 50.000 / 500.000.
/// The first shift pads to 4 digits, since amounts under 1.000 ₫ are rare enough that
/// suggesting 50 or 500 would just waste a chip.
func amountSuggestions(_ value: String, count: Int = 3) -> [String] {
    let digits = value.filter { $0.isNumber }
    guard let parsed = Int64(digits), parsed > 0 else { return [] }

    let firstShift = max(4 - digits.count, 1)
    return (0..<count)
        .map { digits + String(repeating: "0", count: firstShift + $0) }
        .filter { $0.count <= maxAmountDigits }
        .compactMap { shifted in
            Int64(shifted).map { Decimal($0).formatted(groupedDigitsStyle) }
        }
}
