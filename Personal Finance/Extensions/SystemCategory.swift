import Foundation

/// Which bucket a transaction falls into for reporting purposes.
///
/// Only `.operating` counts as earned income or actual spending. The other three
/// move money without earning or spending it, so including them would overstate
/// both sides of every report.
enum ReportingGroup {
    /// Real income and spending — the only group that reaches totals.
    case operating
    /// Wallet-to-wallet moves, including credit card principal payments.
    case transfer
    /// Loan principal: lending, borrowing, collecting, repaying.
    case debt
    /// Bookkeeping corrections from reconciling a wallet.
    case adjustment
}

/// Server-owned categories, identified by `system_key`.
enum SystemCategory {
    static let lendOut = "lend_out"
    static let borrowIn = "borrow_in"
    static let collectDebt = "collect_debt"
    static let repayDebt = "repay_debt"
    static let adjustUp = "adjust_up"
    static let adjustDown = "adjust_down"

    static let debtKeys: Set<String> = [lendOut, borrowIn, collectDebt, repayDebt]
    static let adjustmentKeys: Set<String> = [adjustUp, adjustDown]

    /// Classifies a transaction. Transfers are checked first: a credit card
    /// principal payment is a transfer pair *and* carries a debt-ish category,
    /// and it belongs with transfers.
    ///
    /// A transaction with no category is `.operating` — uncategorised spending is
    /// still spending, and dropping it would quietly shrink every total.
    static func group(
        transferPairId: UUID?,
        systemKey: String?
    ) -> ReportingGroup {
        if transferPairId != nil { return .transfer }
        guard let systemKey else { return .operating }
        if debtKeys.contains(systemKey) { return .debt }
        if adjustmentKeys.contains(systemKey) { return .adjustment }
        return .operating
    }
}

extension LocalTransaction {
    func reportingGroup(systemKeysByCategoryId: [UUID: String]) -> ReportingGroup {
        SystemCategory.group(
            transferPairId: transferPairId,
            systemKey: categoryId.flatMap { systemKeysByCategoryId[$0] }
        )
    }
}

extension Array where Element == LocalCategory {
    /// Lookup used by `reportingGroup(systemKeysByCategoryId:)`. Only system
    /// categories appear — anything missing resolves to `.operating`.
    var systemKeysByCategoryId: [UUID: String] {
        reduce(into: [:]) { map, category in
            if let key = category.systemKey { map[category.serverId] = key }
        }
    }
}

extension Array where Element == LocalTransaction {
    /// Keeps only real income and spending. Use for every total, rate and average.
    /// Transaction lists and wallet history must NOT use this — people need to see
    /// everything that touched their money.
    func operatingOnly(using categories: [LocalCategory]) -> [LocalTransaction] {
        let keys = categories.systemKeysByCategoryId
        return filter { $0.reportingGroup(systemKeysByCategoryId: keys) == .operating }
    }
}
