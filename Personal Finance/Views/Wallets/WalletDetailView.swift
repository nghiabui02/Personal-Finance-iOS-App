import SwiftData
import SwiftUI

struct WalletDetailView: View {
    @Query(sort: \LocalTransaction.transactionDate, order: .reverse)
    private var allTransactions: [LocalTransaction]
    @Query(sort: \LocalWallet.name) private var wallets: [LocalWallet]

    let wallet: LocalWallet

    @State private var metrics = WalletDetailMetrics()
    @State private var activeSheet: WalletDetailSheet?

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
        .onChange(of: allTransactions) { _, _ in recompute() }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        if wallet.type == "credit" {
            ToolbarItem(placement: .topBarLeading) {
                Button("Pay Bill") {
                    activeSheet = .creditPayment
                }
                .disabled(wallet.amountOwed <= 0)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Edit") {
                activeSheet = .edit
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: WalletDetailSheet) -> some View {
        switch sheet {
        case .edit:
            AddEditWalletView(wallet: wallet)
        case .creditPayment:
            CreditPaymentSheet(creditWallet: wallet, wallets: wallets)
        }
    }

    private func recompute() {
        metrics = WalletDetailMetricsCalculator.calculate(
            transactions: allTransactions,
            walletId: wallet.serverId
        )
    }
}

private enum WalletDetailSheet: String, Identifiable {
    case edit
    case creditPayment

    var id: String { rawValue }
}
