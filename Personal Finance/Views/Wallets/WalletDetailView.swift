import SwiftData
import SwiftUI

struct WalletDetailView: View {
    /// The newest rows the list shows, and this month's rows for the totals; a long
    /// history is never loaded in full.
    @Query private var recentTransactions: [LocalTransaction]
    @Query private var monthTransactions: [LocalTransaction]
    @Query(sort: \LocalWallet.name) private var wallets: [LocalWallet]

    let wallet: LocalWallet

    @State private var activeSheet: WalletDetailSheet?

    init(wallet: LocalWallet) {
        self.wallet = wallet
        let walletId: UUID? = wallet.serverId
        var recent = FetchDescriptor<LocalTransaction>(
            predicate: #Predicate { $0.walletId == walletId },
            sortBy: [SortDescriptor(\.transactionDate, order: .reverse)]
        )
        recent.fetchLimit = WalletTransactionsSection.limit
        _recentTransactions = Query(recent)

        let monthStart = LedgerDate.startOfMonth(for: Date()) ?? .distantPast
        let nextMonth = LedgerDate.calendar.date(byAdding: .month, value: 1, to: monthStart) ?? .distantFuture
        _monthTransactions = Query(filter: #Predicate {
            $0.walletId == walletId && $0.transactionDate >= monthStart && $0.transactionDate < nextMonth
        })
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
            WalletTransactionsSection(transactions: recentTransactions)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(wallet.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { detailToolbar }
        .sheet(item: $activeSheet, content: sheetContent)
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

            if wallet.type == .credit {
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

    /// Computed on each render rather than cached: `onChange` compares rows by identity, so a
    /// synced edit to an existing row's amount would leave a cached total stale. The query
    /// is already limited to one wallet and one month.
    private var metrics: WalletDetailMetrics {
        WalletDetailMetricsCalculator.calculate(
            transactions: monthTransactions,
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
