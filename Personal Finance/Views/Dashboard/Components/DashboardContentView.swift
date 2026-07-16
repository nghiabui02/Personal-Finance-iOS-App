import SwiftUI

struct DashboardContentView: View {
    @Binding var selectedMonth: Date

    let metrics: DashboardMetrics
    let syncError: String?
    let isSyncing: Bool
    let currency: String
    let onAddTransaction: () -> Void
    let onAddDebt: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                MonthSelectorView(selectedMonth: $selectedMonth)
                quickActions
                syncErrorSection
                summarySections
                spendingSection
                recentTransactionsSection
                budgetSection
            }
            .padding(.vertical)
        }
    }

    private var quickActions: some View {
        HStack(spacing: 10) {
            Button(action: onAddTransaction) {
                Label("Transaction", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(action: onAddDebt) {
                Label("Debt", systemImage: "person.crop.circle.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
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
            currency: currency
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
