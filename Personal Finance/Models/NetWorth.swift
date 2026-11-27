import Foundation

struct NetWorth {
    var cash: Decimal = 0
    var creditOwed: Decimal = 0
    var lent: Decimal = 0
    var borrowed: Decimal = 0

    var total: Decimal { cash + lent - creditOwed - borrowed }

    static func calculate<Wallet: WalletPosition, Debt: DebtPosition>(
        wallets: [Wallet], debts: [Debt]
    ) -> NetWorth {
        var result = NetWorth()
        for wallet in wallets {
            if wallet.type == .credit {
                result.creditOwed += max(0, (wallet.creditLimit ?? 0) - wallet.balance)
            } else {
                result.cash += wallet.balance
            }
        }
        // The web balance sheet counts active balances. An active debt can be past its due date.
        for debt in debts where debt.status == .active && debt.remainingAmount > 0 {
            switch debt.type {
            case .lend: result.lent += debt.remainingAmount
            case .borrow: result.borrowed += debt.remainingAmount
            }
        }
        return result
    }
}

protocol WalletPosition {
    var type: WalletKind { get }
    var balance: Decimal { get }
    var creditLimit: Decimal? { get }
}

protocol DebtPosition {
    var type: DebtKind { get }
    var status: DebtStatus { get }
    var remainingAmount: Decimal { get }
}

extension LocalWallet: WalletPosition {}
extension RemoteWallet: WalletPosition {}
extension LocalDebt: DebtPosition {}
extension RemoteDebt: DebtPosition {}

/// How far back the net worth chart reaches; sync downloads only these days.
enum NetWorthHistory {
    static let days = 90

    /// First ledger day ("yyyy-MM-dd") the chart shows.
    static func firstDay(now: Date = Date()) -> String {
        LedgerDate.string(from: LedgerDate.calendar.date(byAdding: .day, value: -days, to: now) ?? now)
    }
}
