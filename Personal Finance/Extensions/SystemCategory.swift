import Foundation

/// Server-owned categories, identified by `system_key`.
///
/// The debt keys represent real money leaving or entering a wallet, so they belong
/// in income/expense totals. The two adjustment keys do not: they record a
/// bookkeeping correction from reconciling a wallet, and counting them would make
/// "what did I spend this month" jump every time the user fixes a stale balance.
enum SystemCategory {
    static let adjustUp = "adjust_up"
    static let adjustDown = "adjust_down"

    static func isAdjustment(_ systemKey: String?) -> Bool {
        systemKey == adjustUp || systemKey == adjustDown
    }
}

extension Array where Element == LocalTransaction {
    /// Drops reconciliation adjustments — use for spending/income totals.
    /// Wallet detail deliberately keeps them, so its In/Out matches the rows shown below it.
    func excludingAdjustments(using categories: [LocalCategory]) -> [LocalTransaction] {
        let adjustmentIds = Set(
            categories.filter { SystemCategory.isAdjustment($0.systemKey) }.map(\.serverId)
        )
        guard !adjustmentIds.isEmpty else { return self }
        return filter { tx in
            guard let categoryId = tx.categoryId else { return true }
            return !adjustmentIds.contains(categoryId)
        }
    }
}
