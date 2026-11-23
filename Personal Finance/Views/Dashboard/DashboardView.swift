import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var sync = SyncManager.shared
    @EnvironmentObject private var tabRouter: AppTabRouter

    @Query(sort: \LocalTransaction.transactionDate, order: .reverse)
    private var transactions: [LocalTransaction]
    @Query private var wallets: [LocalWallet]
    @Query private var budgets: [LocalBudget]
    @Query private var debts: [LocalDebt]
    @Query private var categories: [LocalCategory]

    @State private var selectedMonth = TransactionDateRange.monthStart(for: Date())
    @State private var quickAction: DashboardQuickAction?

    private let currency = "VND"

    var body: some View {
        NavigationStack {
            dashboardScreen
        }
    }

    private var dashboardScreen: some View {
        DashboardContentView(
            selectedMonth: $selectedMonth,
            metrics: metrics,
            syncError: sync.syncError,
            isSyncing: sync.isSyncing,
            currency: currency,
            onAddTransaction: { quickAction = .transaction },
            onAddTransfer: { quickAction = .transfer },
            onAddDebt: { quickAction = .debtPayment },
            onViewAllTransactions: { tabRouter.selectedTab = .transactions }
        )
            .background(Color(.systemGroupedBackground))
            .appScreenHeader("Overview")
            .sheet(item: $quickAction, content: quickActionSheet)
            .refreshable { await sync.syncAll(modelContext: modelContext) }
    }

    @ViewBuilder
    private func quickActionSheet(_ action: DashboardQuickAction) -> some View {
        switch action {
        case .transaction:
            AddEditTransactionView(transaction: nil)
        case .transfer:
            TransferSheet(wallets: Array(wallets))
        case .debtPayment:
            AddEditDebtView(debt: nil)
        }
    }

    private var metrics: DashboardMetrics {
        DashboardMetricsCalculator.calculate(
            transactions: transactions,
            categories: categories,
            wallets: wallets,
            budgets: budgets,
            debts: debts,
            selectedMonth: selectedMonth,
            currency: currency
        )
    }
}

private enum DashboardQuickAction: String, Identifiable {
    case transaction, transfer, debtPayment

    var id: String { rawValue }
}
