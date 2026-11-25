import SwiftData
import SwiftUI

struct WalletDetailView: View {
    /// Only this wallet's history, not every transaction in the ledger.
    @Query private var walletTransactions: [LocalTransaction]
    @Query(sort: \LocalWallet.name) private var wallets: [LocalWallet]

    let wallet: LocalWallet

    @State private var metrics = WalletDetailMetrics()
    @State private var activeSheet: WalletDetailSheet?

    init(wallet: LocalWallet) {
        self.wallet = wallet
        let walletId: UUID? = wallet.serverId
        _walletTransactions = Query(
            filter: #Predicate { $0.walletId == walletId },
            sort: \LocalTransaction.transactionDate, order: .reverse
        )
    }

    var body: some View {
        List {
            Section {
                WalletDetailHeader(wallet: wallet)
            }
            WalletCashFlowSection(
                income: metrics.monthlyIncome,
                expense: metrics.monthlyExpense
            )
            WalletInformationSection(wallet: wallet)
            WalletTransactionsSection(transactions: metrics.transactions)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(wallet.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { detailToolbar }
        .sheet(item: $activeSheet, content: sheetContent)
        .onAppear(perform: recompute)
        .onChange(of: walletTransactions) { _, _ in recompute() }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            if wallets.count >= 2 {
                Button {
                    activeSheet = .transfer
                } label: {
                    Label("Transfer", systemImage: "arrow.left.arrow.right")
                }
            }

            if wallet.type == "credit" {
                Button("Pay Bill") {
                    activeSheet = .creditPayment
                }
                .disabled(wallet.amountOwed <= 0)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Reconcile Balance") { activeSheet = .reconcile }
                Button("Edit") { activeSheet = .edit }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: WalletDetailSheet) -> some View {
        switch sheet {
        case .edit:
            AddEditWalletView(wallet: wallet)
        case .transfer:
            TransferSheet(
                wallets: wallets,
                initialFromWalletId: wallet.serverId
            )
        case .creditPayment:
            CreditPaymentSheet(creditWallet: wallet, wallets: wallets)
        case .reconcile:
            ReconcileSheet(wallet: wallet)
        }
    }

    private func recompute() {
        metrics = WalletDetailMetricsCalculator.calculate(
            transactions: walletTransactions,
            walletId: wallet.serverId
        )
    }
}

private enum WalletDetailSheet: String, Identifiable {
    case edit
    case transfer
    case creditPayment
    case reconcile

    var id: String { rawValue }
}
