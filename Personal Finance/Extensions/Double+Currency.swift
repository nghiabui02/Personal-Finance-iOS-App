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
