import SwiftUI
import SwiftData

struct ReportsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalTransaction.transactionDate, order: .reverse) private var allTx: [LocalTransaction]
    @Query private var wallets: [LocalWallet]
    @Query private var debts: [LocalDebt]
    @Query private var categories: [LocalCategory]
    @StateObject private var sync = SyncManager.shared

    @State private var selectedPeriod: ReportPeriod = .week
    @State private var referenceDate = Date()
    @State private var metrics = ReportMetrics()

    private var periodContext: ReportPeriodContext {
        ReportPeriodContext(period: selectedPeriod, referenceDate: referenceDate)
    }

    var body: some View {
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
            .onAppear { recomputeMetrics() }
            .onChange(of: allTx) { _, _ in recomputeMetrics() }
            .onChange(of: selectedPeriod) { _, _ in recomputeMetrics() }
            .onChange(of: referenceDate) { _, _ in recomputeMetrics() }
        }
    }

    private func navigatePeriod(by delta: Int) {
        guard let nextDate = periodContext.date(byAdding: delta) else { return }
        withAnimation { referenceDate = nextDate }
    }

    private func recomputeMetrics() {
        // Only "adjust_up"/"adjust_down" (balance reconciliation) are excluded —
        // debt system categories (repay_debt/collect_debt/...) are real cash
        // movement and belong in income/expense totals.
        let adjustmentCategoryIds = Set(categories.filter {
            $0.systemKey == "adjust_up" || $0.systemKey == "adjust_down"
        }.map(\.serverId))
        let realTx = allTx.filter { tx in
            guard let catId = tx.categoryId else { return true }
            return !adjustmentCategoryIds.contains(catId)
        }
        metrics = ReportMetricsCalculator.calculate(
            transactions: realTx,
            wallets: wallets,
            debts: debts,
            context: periodContext
        )
    }
}
