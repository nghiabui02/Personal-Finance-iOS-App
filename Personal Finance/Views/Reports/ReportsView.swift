import SwiftUI
import SwiftData

struct ReportsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalTransaction.transactionDate, order: .reverse) private var allTx: [LocalTransaction]
    @Query private var wallets: [LocalWallet]
    @Query private var budgets: [LocalBudget]
    @Query private var debts: [LocalDebt]
    @Query private var categories: [LocalCategory]
    @StateObject private var sync = SyncManager.shared

    @State private var selectedPeriod: ReportPeriod = .week
    @State private var referenceDate = Date()

    private var periodContext: ReportPeriodContext {
        ReportPeriodContext(period: selectedPeriod, referenceDate: referenceDate)
    }

    var body: some View {
        let metrics = ReportMetricsCalculator.calculate(
            transactions: allTx,
            categories: categories,
            wallets: wallets,
            debts: debts,
            budgets: budgets,
            snapshots: sync.netWorthSnapshots,
            context: periodContext
        )
        NavigationStack {
            ReportsContentView(
                selectedPeriod: $selectedPeriod,
                metrics: metrics,
                rangeLabel: periodContext.rangeLabel,
                isCurrentPeriod: periodContext.isCurrent,
                onNavigatePeriod: navigatePeriod
            )
            .appScreenHeader("Reports")
            .refreshable { await sync.syncAll(modelContext: modelContext) }

        }
    }

    private func navigatePeriod(by delta: Int) {
        guard let nextDate = periodContext.date(byAdding: delta) else { return }
        withAnimation { referenceDate = nextDate }
    }
}
