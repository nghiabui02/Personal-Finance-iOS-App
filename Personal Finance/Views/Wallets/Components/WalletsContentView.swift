import SwiftUI

struct WalletsContentView: View {
    let wallets: [LocalWallet]
    let metrics: WalletListMetrics
    let onTransfer: (LocalWallet?) -> Void
    let onAdd: () -> Void
    let onEdit: (LocalWallet) -> Void
    let onPayCredit: (LocalWallet) -> Void
    let onDelete: (LocalWallet) -> Void
    let onNavigate: (LocalWallet) -> Void
    let onRefresh: () async -> Void

    var body: some View {
        List {
            Section {
                WalletSummaryCard(
                    totalBalance: metrics.totalBalance,
                    walletCount: metrics.walletCount
                )
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

            Section {
                HStack {
                    Text("\(wallets.count) WALLETS")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1)
                    Spacer()
                    Button(action: onAdd) {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.caption.weight(.bold))
                            Text("New wallet")
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color(.separator), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

            Section {
                if wallets.isEmpty {
                    ContentUnavailableView(
                        "No Wallets",
                        systemImage: "creditcard",
                        description: Text("Tap + to add your first wallet")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    walletCards
                }
            }
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .refreshable { await onRefresh() }
    }

    private var walletCards: some View {
        ForEach(wallets, id: \.serverId) { wallet in
            WalletRow(
                wallet: wallet,
                canTransfer: metrics.canTransfer,
                onTransfer: { onTransfer(wallet) },
                onEdit: { onEdit(wallet) },
                onPayCredit: { onPayCredit(wallet) },
                onNavigate: { onNavigate(wallet) }
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button { onDelete(wallet) } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            }
        }
    }
}
