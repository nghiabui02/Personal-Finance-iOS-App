import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var authVM: AuthViewModel
    @StateObject private var sync = SyncManager.shared

    @State private var selectedMonth: Date = {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
    }()

    @Query(sort: \LocalTransaction.transactionDate, order: .reverse) private var allTransactions: [LocalTransaction]
    @Query private var wallets: [LocalWallet]
    @Query private var allBudgets: [LocalBudget]

    // MARK: - Computed: filter by selected month

    private var monthlyTransactions: [LocalTransaction] {
        let cal = Calendar.current
        return allTransactions.filter {
            cal.isDate($0.transactionDate, equalTo: selectedMonth, toGranularity: .month)
        }
    }

    private var monthlyIncome: Double {
        monthlyTransactions.filter { $0.type == "income" }.reduce(0) { $0 + $1.amount }
    }

    private var monthlyExpense: Double {
        monthlyTransactions.filter { $0.type == "expense" }.reduce(0) { $0 + $1.amount }
    }

    private var netBalance: Double { monthlyIncome - monthlyExpense }

    private var recentTransactions: [LocalTransaction] {
        Array(monthlyTransactions.prefix(7))
    }

    private var primaryCurrency: String { "VND" }

    private var currentBudgets: [LocalBudget] {
        let cal = Calendar.current
        return allBudgets.filter {
            cal.isDate($0.month, equalTo: selectedMonth, toGranularity: .month)
        }
    }

    // Group expense spending per categoryId
    private var spendingByCategoryId: [String: Double] {
        var result: [String: Double] = [:]
        for tx in monthlyTransactions where tx.type == "expense" {
            let key = tx.categoryId ?? ""
            result[key, default: 0] += tx.amount
        }
        return result
    }

    // Top 5 expense categories for chart
    private var spendingItems: [CategorySpending] {
        var grouped: [String: (name: String, icon: String, color: String?, total: Double)] = [:]
        for tx in monthlyTransactions where tx.type == "expense" {
            let key = tx.categoryId ?? tx.categoryName ?? "other"
            let existing = grouped[key]
            grouped[key] = (
                name: existing?.name ?? tx.categoryName ?? "Other",
                icon: existing?.icon ?? tx.categoryIcon ?? "💸",
                color: existing?.color ?? tx.categoryColor,
                total: (existing?.total ?? 0) + tx.amount
            )
        }
        let sorted = grouped.values.sorted { $0.total > $1.total }.prefix(5)
        let total = sorted.reduce(0) { $0 + $1.total }
        let palette: [Color] = [.blue, .indigo, .purple, .pink, .orange]
        return sorted.enumerated().map { i, item in
            CategorySpending(
                id: item.name,
                name: item.name,
                icon: item.icon,
                color: item.color.map { Color(hex: $0) } ?? palette[i % palette.count],
                amount: item.total,
                percentage: total > 0 ? (item.total / total) * 100 : 0
            )
        }
    }

    // MARK: - View

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    MonthSelectorView(selectedMonth: $selectedMonth)

                    if let err = sync.syncError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                            Text(err).font(.caption).foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    // Stat cards
                    HStack(spacing: 10) {
                        StatCardView(title: "Income",  amount: monthlyIncome,  color: .green, icon: "arrow.down.circle.fill", currency: primaryCurrency)
                        StatCardView(title: "Expenses", amount: monthlyExpense, color: .red,   icon: "arrow.up.circle.fill",   currency: primaryCurrency)
                        StatCardView(title: "Balance",  amount: netBalance,    color: netBalance >= 0 ? .blue : .red, icon: "equal.circle.fill", currency: primaryCurrency)
                    }
                    .padding(.horizontal)

                    // Spending chart
                    SpendingChartView(
                        items: spendingItems,
                        total: monthlyExpense,
                        currency: primaryCurrency
                    )
                    .padding(.horizontal)

                    // Recent transactions
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Transactions")
                            .font(.headline)
                            .padding(.horizontal)

                        if recentTransactions.isEmpty && !sync.isSyncing {
                            ContentUnavailableView("No Transactions",
                                                   systemImage: "tray",
                                                   description: Text("Pull down to refresh"))
                                .padding(.vertical, 8)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(recentTransactions) { tx in
                                    RecentTransactionRowView(transaction: tx, currency: primaryCurrency)
                                    if tx.serverId != recentTransactions.last?.serverId {
                                        Divider().padding(.leading, 56)
                                    }
                                }
                            }
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                    }

                    // Budget progress
                    BudgetProgressView(
                        budgets: currentBudgets,
                        spendingByCategoryId: spendingByCategoryId,
                        currency: primaryCurrency
                    )
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Overview")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { statusIcon }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out") { Task { await authVM.signOut() } }
                        .foregroundColor(.red)
                }
            }
            .refreshable { await sync.syncAll(modelContext: modelContext) }
            .onAppear {
                Task { await sync.syncAll(modelContext: modelContext) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .networkRestored)) { _ in
                Task { await sync.syncAll(modelContext: modelContext) }
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if sync.isSyncing {
            ProgressView().scaleEffect(0.8)
        } else if !sync.isOnline {
            Label("No Internet", systemImage: "wifi.slash")
                .labelStyle(.iconOnly)
                .foregroundColor(.orange)
        }
    }
}

// Compact stat card (3 in a row)
private struct StatCardView: View {
    let title: String
    let amount: Double
    let color: Color
    let icon: String
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon).foregroundColor(color).font(.caption)
                Text(title).font(.caption).foregroundColor(.secondary)
            }
            Text(amount.formatted(currency: currency))
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(color)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}
