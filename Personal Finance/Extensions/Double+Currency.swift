import Foundation

private let _vndFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "VND"
    f.maximumFractionDigits = 0
    f.minimumFractionDigits = 0
    return f
}()

private let _decimalFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = 0
    return f
}()

extension Double {
    func formatted(currency: String) -> String {
        if currency == "VND" {
            return _vndFormatter.string(from: NSNumber(value: self)) ?? "\(self)"
        }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        return f.string(from: NSNumber(value: self)) ?? "\(self)"
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
