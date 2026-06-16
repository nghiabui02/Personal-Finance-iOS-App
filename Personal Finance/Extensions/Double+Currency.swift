import Foundation

extension Double {
    func formatted(currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        if currency == "VND" {
            formatter.maximumFractionDigits = 0
            formatter.minimumFractionDigits = 0
        }
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }

    // Format as xxx,xxx,xxx for display in amount text fields
    func formattedDecimal() -> String {
        guard self > 0 else { return "" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: self)) ?? "\(Int(self))"
    }
}

// Shared onChange handler logic — call from every amount TextField
func applyAmountFormat(new: String, amountText: inout String, amount: inout Double) {
    let digits = new.filter { $0.isNumber }
    if digits.isEmpty {
        amountText = ""
        amount = 0
    } else if let v = Int64(digits) {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        amountText = f.string(from: NSNumber(value: v)) ?? digits
        amount = Double(v)
    }
}
