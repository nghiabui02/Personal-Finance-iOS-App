import Foundation

struct WalletListMetrics {
    var netWorth: Double = 0
    var walletCount: Int = 0

    var canTransfer: Bool { walletCount >= 2 }
}

enum WalletListMetricsCalculator {
    static func calculate(wallets: [LocalWallet]) -> WalletListMetrics {
        let nonCredit = wallets
            .filter { $0.type != "credit" }
            .reduce(0.0) { $0 + $1.balance }
        let creditDebt = wallets
            .filter { $0.type == "credit" }
            .reduce(0.0) { $0 + $1.amountOwed }

        return WalletListMetrics(
            netWorth: nonCredit - creditDebt,
            walletCount: wallets.count
        )
    }
}
