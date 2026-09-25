import Foundation

private let _vndFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.locale = Locale(identifier: "vi_VN")
    f.currencyCode = "VND"
    f.currencySymbol = "₫"
    f.maximumFractionDigits = 0
    f.minimumFractionDigits = 0
    return f
}()

private let _decimalFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "vi_VN")
    f.maximumFractionDigits = 0
    return f
}()

private var _otherFormatters: [String: NumberFormatter] = [:]
private func otherFormatter(currency: String) -> NumberFormatter {
    if let cached = _otherFormatters[currency] { return cached }
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = currency
    _otherFormatters[currency] = f
    return f
}

extension Double {
    func formatted(currency: String) -> String {
        if currency == "VND" {
            return _vndFormatter.string(from: NSNumber(value: self)) ?? "\(self)"
        }
        return otherFormatter(currency: currency).string(from: NSNumber(value: self)) ?? "\(self)"
    }

    func formattedDecimal() -> String {
        guard self > 0 else { return "" }
        return _decimalFormatter.string(from: NSNumber(value: self)) ?? "\(Int(self))"
    }
}

/// Upper bound shared by every currency field: 999.999.999.999 ₫
let maxAmountDigits = 12

func applyAmountFormat(new: String, amountText: inout String, amount: inout Double) {
    let digits = new.filter { $0.isNumber }
    if digits.isEmpty {
        amountText = ""
        amount = 0
    } else if let v = Int64(digits) {
        amountText = _decimalFormatter.string(from: NSNumber(value: v)) ?? digits
        amount = Double(v)
    }
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
            Int64(shifted).flatMap { _decimalFormatter.string(from: NSNumber(value: $0)) }
        }
}
