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
}
