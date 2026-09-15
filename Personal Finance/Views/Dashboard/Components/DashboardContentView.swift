import SwiftUI

struct DashboardContentView: View {
    @Binding var selectedMonth: Date

    let metrics: DashboardMetrics
    let syncError: String?
    let isSyncing: Bool
    let currency: String
    let onAddTransaction: () -> Void
    let onAddTransfer: () -> Void
    let onAddDebt: () -> Void
    let onViewAllTransactions: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                topRow
                syncErrorSection
                spendingPaceSection
                summarySections
                spendingSection
                recentTransactionsSection
                budgetSection
            }
            .padding(.vertical)
        }
    }

    private var topRow: some View {
        HStack(spacing: 8) {
            MonthSelectorView(selectedMonth: $selectedMonth)
            Spacer()
            Button(action: onAddTransaction) {
                Image(systemName: "plus.circle.fill")
            }
            .help("New Transaction")
            Button(action: onAddTransfer) {
                Image(systemName: "arrow.left.arrow.right.circle.fill")
            }
            .help("Transfer")
            Button(action: onAddDebt) {
                Image(systemName: "person.crop.circle.badge.plus")
            }
            .help("Add Debt")
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var syncErrorSection: some View {
        if let syncError {
            Label(syncError, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var spendingPaceSection: some View {
        if let pct = metrics.spendingPaceDeltaPct, abs(pct) >= 0.05 {
            Label(
                "\(abs(pct * 100).formatted(.number.precision(.fractionLength(0))))% \(pct > 0 ? "above" : "below") your usual pace",
                systemImage: pct > 0 ? "arrow.up.right" : "arrow.down.right"
            )
            .font(.caption)
            .foregroundStyle(pct > 0 ? Color.expense : Color.income)
            .padding(.horizontal)
        }
    }

    private var summarySections: some View {
        Group {
            DashboardOverviewCard(
                netBalance: metrics.netBalance,
                income: metrics.income,
                expense: metrics.expense,
                currency: currency
            )
            .padding(.horizontal)

            DashboardNetWorthCard(
                netWorth: metrics.netWorth,
                cash: metrics.cash,
                lent: metrics.outstandingLent,
                borrowed: metrics.outstandingBorrowed,
                currency: currency
            )
            .padding(.horizontal)

            if !metrics.alerts.isEmpty {
                DashboardAlertsCard(alerts: metrics.alerts)
                    .padding(.horizontal)
            }
        }
    }

    private var spendingSection: some View {
        SpendingChartView(
            items: metrics.spendingItems,
            total: metrics.expense,
            currency: currency
        )
        .padding(.horizontal)
    }

    private var recentTransactionsSection: some View {
        DashboardRecentTransactionsSection(
            transactions: metrics.recentTransactions,
            isSyncing: isSyncing,
            currency: currency,
            onViewAll: onViewAllTransactions
        )
    }

    private var budgetSection: some View {
        BudgetProgressView(
            budgets: metrics.currentBudgets,
            spendingByCategoryId: metrics.spendingByCategoryId,
            currency: currency
        )
        .padding(.horizontal)
    }
}
