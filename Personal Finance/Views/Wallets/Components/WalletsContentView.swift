import SwiftUI

struct WalletsContentView: View {
    let wallets: [LocalWallet]
    let metrics: WalletListMetrics
    let onTransfer: (LocalWallet?) -> Void
    let onPayCredit: (LocalWallet) -> Void
    let onDelete: (LocalWallet) -> Void
    let onRefresh: () async -> Void

    var body: some View {
        List {
            Section {
                WalletSummaryCard(netWorth: metrics.netWorth)
            }

            Section(wallets.isEmpty ? "" : "\(wallets.count) wallets") {
                if wallets.isEmpty {
                    ContentUnavailableView(
                        "No Wallets",
                        systemImage: "creditcard",
                        description: Text("Tap + to add your first wallet")
                    )
                    .padding(.vertical)
                } else {
                    walletRows
                }
            }
        }
        .refreshable { await onRefresh() }
    }

    private var walletRows: some View {
        ForEach(wallets, id: \.serverId) { wallet in
            NavigationLink {
                WalletDetailView(wallet: wallet)
            } label: {
                WalletRow(wallet: wallet)
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if metrics.canTransfer {
                    Button {
                        onTransfer(wallet)
                    } label: {
                        Label("Transfer", systemImage: "arrow.left.arrow.right")
                    }
                    .tint(.blue)
                }

                if wallet.type == "credit" {
                    Button {
                        onPayCredit(wallet)
                    } label: {
                        Label("Pay Bill", systemImage: "creditcard.fill")
                    }
                    .tint(.green)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    onDelete(wallet)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            }
        }
    }
}
