import SwiftUI
import SwiftData

struct ReportsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var wallets: [LocalWallet]
    @Query private var budgets: [LocalBudget]
    @Query private var debts: [LocalDebt]
    @Query private var categories: [LocalCategory]
    private var sync: SyncManager { .shared }

    @State private var selectedPeriod: ReportPeriod = .week
    @State private var referenceDate = Date()

    private var periodContext: ReportPeriodContext {
        ReportPeriodContext(period: selectedPeriod, referenceDate: referenceDate)
    }

    /// The reported period, plus the earlier months a monthly report's rollover budgets carry from.
    private var transactionWindow: Range<Date> {
        let range = periodContext.range
        let dayAfterEnd = periodContext.calendar.date(byAdding: .day, value: 1, to: range.end) ?? .distantFuture
        let window = range.start..<dayAfterEnd
        guard selectedPeriod == .month else { return window }
        return TransactionDateRange.including(budgetHistoryOf: budgets, for: referenceDate, in: window)
    }

    var body: some View {
        NavigationStack {
            TransactionsInRange(transactionWindow) { transactions in
                ReportsContentView(
                    selectedPeriod: $selectedPeriod,
                    metrics: metrics(for: transactions),
                    rangeLabel: periodContext.rangeLabel,
                    isCurrentPeriod: periodContext.isCurrent,
                    onNavigatePeriod: navigatePeriod
                )
            }
            .appScreenHeader("Reports")
            .refreshable { await sync.syncAll(modelContext: modelContext) }

        }
    }

    private func metrics(for transactions: [LocalTransaction]) -> ReportMetrics {
        ReportMetricsCalculator.calculate(
            transactions: transactions,
            categories: categories,
            wallets: wallets,
            debts: debts,
            budgets: budgets,
            snapshots: sync.netWorthSnapshots,
            context: periodContext
        )
    }

    private func navigatePeriod(by delta: Int) {
        guard let nextDate = periodContext.date(byAdding: delta) else { return }
        withAnimation { referenceDate = nextDate }
    }
}
