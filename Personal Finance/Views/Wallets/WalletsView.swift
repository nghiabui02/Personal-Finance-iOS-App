import SwiftUI
import SwiftData

struct WalletsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalWallet.name) private var wallets: [LocalWallet]
    @StateObject private var sync = SyncManager.shared

    @State private var showAdd = false
    @State private var showTransfer = false
    @State private var transferSourceWalletId: UUID?
    @State private var payingCreditWallet: LocalWallet?
    @State private var pendingDeletion: LocalWallet?
    @State private var showDeleteConfirmation = false
    @State private var errorMsg: String?

    private var metrics: WalletListMetrics {
        WalletListMetricsCalculator.calculate(wallets: wallets)
    }

    var body: some View {
        NavigationStack {
            WalletsContentView(
                wallets: wallets,
                metrics: metrics,
                onTransfer: startTransfer,
                onPayCredit: { payingCreditWallet = $0 },
                onDelete: requestDelete,
                onRefresh: { await sync.syncAll(modelContext: modelContext) }
            )
            .navigationTitle("Wallets")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if metrics.canTransfer {
                        Button {
                            startTransfer(from: nil)
                        } label: {
                            Label("Transfer", systemImage: "arrow.left.arrow.right")
                                .labelStyle(.titleAndIcon)
                                .font(.subheadline)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                AddEditWalletView(wallet: nil)
            }
            .sheet(
                isPresented: $showTransfer,
                onDismiss: { transferSourceWalletId = nil }
            ) {
                TransferSheet(
                    wallets: wallets,
                    initialFromWalletId: transferSourceWalletId
                )
            }
            .sheet(item: $payingCreditWallet) { wallet in
                CreditPaymentSheet(creditWallet: wallet, wallets: wallets)
            }
            .deleteConfirmation(
                item: $pendingDeletion,
                isPresented: $showDeleteConfirmation,
                title: "Delete Wallet?",
                message: "The wallet will be permanently deleted. Any positive balance may be moved to your default wallet."
            ) { wallet in
                Task { await deleteWallet(wallet) }
            }
            .errorAlert($errorMsg)
        }
    }

    private func startTransfer(from wallet: LocalWallet?) {
        transferSourceWalletId = wallet?.serverId
        showTransfer = true
    }

    private func requestDelete(_ wallet: LocalWallet) {
        pendingDeletion = wallet
        showDeleteConfirmation = true
    }

    private func deleteWallet(_ wallet: LocalWallet) async {
        do {
            try await WalletService.shared.delete(wallet, in: modelContext)
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}
