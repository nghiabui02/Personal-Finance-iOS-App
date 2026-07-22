import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var sync = SyncManager.shared
    @EnvironmentObject private var tabRouter: AppTabRouter

    @Query(sort: \LocalTransaction.transactionDate, order: .reverse)
    private var transactions: [LocalTransaction]
    @Query private var wallets: [LocalWallet]
    @Query private var budgets: [LocalBudget]
    @Query private var debts: [LocalDebt]

    @State private var selectedMonth = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    )!
    @State private var metrics = DashboardMetrics()
    @State private var quickAction: DashboardQuickAction?
    @State private var networkObserver: NSObjectProtocol?

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
                onViewAllTransactions: { tabRouter.selectedTab = .transactions }
        )
            .background(Color(.systemGroupedBackground))
            .appScreenHeader("Overview")
            .sheet(item: $quickAction, content: quickActionSheet)
            .refreshable { await sync.syncAll(modelContext: modelContext) }
            .onAppear(perform: handleAppear)
            .onDisappear(perform: removeNetworkObserver)
            .onChange(of: transactions) { _, _ in recompute() }
            .onChange(of: wallets) { _, _ in recompute() }
            .onChange(of: budgets) { _, _ in recompute() }
            .onChange(of: debts) { _, _ in recompute() }
            .onChange(of: selectedMonth) { _, _ in recompute() }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                handleScenePhaseChange(oldPhase, newPhase)
            }
    }

    @ViewBuilder
    private func quickActionSheet(_ action: DashboardQuickAction) -> some View {
        switch action {
        case .transaction:
            AddEditTransactionView(transaction: nil)
        }
    }

    private func recompute() {
        metrics = DashboardMetricsCalculator.calculate(
            transactions: transactions,
            wallets: wallets,
            budgets: budgets,
            debts: debts,
            selectedMonth: selectedMonth,
            currency: currency
        )
    }

    private func handleAppear() {
        recompute()
        syncData()
        installNetworkObserver()
    }

    private func handleScenePhaseChange(
        _ oldPhase: ScenePhase,
        _ newPhase: ScenePhase
    ) {
        if newPhase == .active {
            syncData()
        }
    }

    private func syncData() {
        Task { @MainActor in
            await sync.syncAll(modelContext: modelContext)
        }
    }

    private func installNetworkObserver() {
        guard networkObserver == nil else { return }
        networkObserver = NotificationCenter.default.addObserver(
            forName: .networkRestored,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await sync.syncAll(modelContext: modelContext)
            }
        }
    }

    private func removeNetworkObserver() {
        guard let networkObserver else { return }
        NotificationCenter.default.removeObserver(networkObserver)
        self.networkObserver = nil
    }
}

private enum DashboardQuickAction: String, Identifiable {
    case transaction

    var id: String { rawValue }
}
