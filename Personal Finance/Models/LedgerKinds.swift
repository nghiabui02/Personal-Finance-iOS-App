import Foundation

/// A value the database stores as text and checks with a `CHECK (... IN ...)` constraint.
///
/// Decoding never fails on a value this build does not know: a kind added on the
/// server degrades to `fallback` instead of failing the whole sync.
protocol LedgerKind: RawRepresentable<String>, Codable, Hashable, Sendable, CaseIterable {
    static var fallback: Self { get }
}

extension LedgerKind {
    init(wireValue raw: String) {
        self = Self(rawValue: raw) ?? Self(rawValue: raw.lowercased()) ?? .fallback
    }

    init(from decoder: any Decoder) throws {
        self.init(wireValue: try decoder.singleValueContainer().decode(String.self))
    }
}

/// `transactions.type`, also the kind of a category or recurring rule.
enum TransactionKind: String, LedgerKind {
    case income, expense
    static let fallback = Self.expense
}

/// `wallets.type`.
enum WalletKind: String, LedgerKind {
    case cash, bank
    case eWallet = "e_wallet"
    case investment, credit, other
    static let fallback = Self.other
}

/// `debts.type`: money this user lent out, or borrowed.
enum DebtKind: String, LedgerKind {
    case lend, borrow
    static let fallback = Self.borrow
}

/// `debts.status`.
enum DebtStatus: String, LedgerKind {
    case active, overdue, completed
    static let fallback = Self.active
}

/// `saving_goals.status`.
enum GoalStatus: String, LedgerKind {
    case active, completed, cancelled
    static let fallback = Self.active
}

/// `recurring_transactions.frequency`.
enum RecurringFrequency: String, LedgerKind {
    case daily, weekly, monthly, yearly
    static let fallback = Self.monthly
}

/// `debt_payments.type`: a repayment, or more money added to the same debt.
enum DebtPaymentKind: String, LedgerKind {
    case payment, addition
    static let fallback = Self.payment
}
