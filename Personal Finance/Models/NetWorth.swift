import Foundation

struct NetWorth {
    var cash = 0.0
    var creditOwed = 0.0
    var lent = 0.0
    var borrowed = 0.0

    var total: Double { cash + lent - creditOwed - borrowed }

    static func calculate<Wallet: WalletPosition, Debt: DebtPosition>(
        wallets: [Wallet], debts: [Debt]
    ) -> NetWorth {
        var result = NetWorth()
        for wallet in wallets {
            if wallet.type == "credit" {
                result.creditOwed += max(0, (wallet.creditLimit ?? 0) - wallet.balance)
            } else {
                result.cash += wallet.balance
            }
        }
        // The web balance sheet counts active balances. An active debt can be past its due date.
        for debt in debts where debt.status == "active" && debt.remainingAmount > 0 {
            if debt.type == "lend" { result.lent += debt.remainingAmount }
            if debt.type == "borrow" { result.borrowed += debt.remainingAmount }
        }
        return result
    }
}

protocol WalletPosition {
    var type: String { get }
    var balance: Double { get }
    var creditLimit: Double? { get }
}

protocol DebtPosition {
    var type: String { get }
    var status: String { get }
    var remainingAmount: Double { get }
}

extension LocalWallet: WalletPosition {}
extension RemoteWallet: WalletPosition {}
extension LocalDebt: DebtPosition {}
extension RemoteDebt: DebtPosition {}
