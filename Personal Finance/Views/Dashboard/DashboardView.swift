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
    @Query private var categories: [LocalCategory]

    @State private var selectedMonth = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    )!
    @State private var metrics = DashboardMetrics()
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
            .onAppear(perform: handleAppear)
            .onChange(of: transactions) { _, _ in recompute() }
            .onChange(of: wallets) { _, _ in recompute() }
            .onChange(of: budgets) { _, _ in recompute() }
            .onChange(of: debts) { _, _ in recompute() }
            .onChange(of: categories) { _, _ in recompute() }
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
        case .transfer:
            TransferSheet(wallets: Array(wallets))
        case .debtPayment:
            AddEditDebtView(debt: nil)
        }
    }

    private func recompute() {
        // Only "adjust_up"/"adjust_down" (balance reconciliation) are excluded —
        // debt system categories (repay_debt/collect_debt/...) are real cash
        // movement and belong in income/expense totals.
        let adjustmentCategoryIds = Set(categories.filter {
            $0.systemKey == "adjust_up" || $0.systemKey == "adjust_down"
        }.map(\.serverId))
        let realTx = transactions.filter { tx in
            guard let catId = tx.categoryId else { return true }
            return !adjustmentCategoryIds.contains(catId)
        }
        metrics = DashboardMetricsCalculator.calculate(
            transactions: realTx,
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
        Task { await writeNetWorthSnapshot(metrics.netWorth) }
    }

    private func writeNetWorthSnapshot(_ netWorth: Double) async {
        guard let userId = try? await SupabaseService.shared.client.auth.session.user.id else { return }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        let today = df.string(from: Date())
        struct Body: Encodable { let user_id: String; let net_worth: Double; let recorded_date: String }
        try? await SupabaseService.shared.client
            .from("net_worth_snapshots")
            .upsert(Body(user_id: userId.uuidString.lowercased(), net_worth: netWorth, recorded_date: today),
                    onConflict: "user_id,recorded_date")
            .execute()
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


}

private enum DashboardQuickAction: String, Identifiable {
    case transaction, transfer, debtPayment

    var id: String { rawValue }
}
