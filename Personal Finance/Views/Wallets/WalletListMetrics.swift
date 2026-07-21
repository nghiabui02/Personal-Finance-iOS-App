import Foundation

struct WalletListMetrics {
    var totalBalance: Double = 0
    var walletCount: Int = 0

    var canTransfer: Bool { walletCount >= 2 }
}

enum WalletListMetricsCalculator {
    static func calculate(wallets: [LocalWallet]) -> WalletListMetrics {
        let totalBalance = wallets
            .filter { $0.type != "credit" }
            .reduce(0.0) { $0 + $1.balance }

        return WalletListMetrics(
            totalBalance: totalBalance,
            walletCount: wallets.count
        )
    }
}
