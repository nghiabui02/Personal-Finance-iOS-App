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

    // Cached — computed once per month/data change, not on every render
    @State private var monthlyIncome:  Double = 0
    @State private var monthlyExpense: Double = 0
    @State private var recentTransactions: [LocalTransaction] = []
    @State private var spendingByCategoryId: [UUID: Double] = [:]
    @State private var spendingItems: [CategorySpending] = []
    @State private var currentBudgets: [LocalBudget] = []

    private var netBalance: Double { monthlyIncome - monthlyExpense }
    private let primaryCurrency = "VND"

    // MARK: - View

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
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
                        StatCardView(title: "Income",  amount: monthlyIncome,  color: .income,  icon: "arrow.down.circle.fill", currency: primaryCurrency)
                        StatCardView(title: "Expenses", amount: monthlyExpense, color: .expense, icon: "arrow.up.circle.fill",   currency: primaryCurrency)
                        StatCardView(title: "Balance",  amount: netBalance,    color: netBalance >= 0 ? .blue : .expense, icon: "equal.circle.fill", currency: primaryCurrency)
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
                            let lastId = recentTransactions.last?.serverId
                            VStack(spacing: 0) {
                                ForEach(recentTransactions) { tx in
                                    RecentTransactionRowView(transaction: tx, currency: primaryCurrency)
                                    if tx.serverId != lastId {
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
            .gesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { value in
                        let h = value.translation.width
                        let v = value.translation.height
                        guard abs(h) > abs(v) * 2, abs(h) > 60 else { return }
                        let delta = h < 0 ? 1 : -1
                        if let next = Calendar.current.date(byAdding: .month, value: delta, to: selectedMonth) {
                            withAnimation { selectedMonth = next }
                        }
                    }
            )
            .navigationTitle("Overview")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { statusIcon }
            }
            .refreshable { await sync.syncAll(modelContext: modelContext) }
            .onAppear {
                recompute()
                Task { await sync.syncAll(modelContext: modelContext) }
            }
            .onChange(of: allTransactions) { _, _ in recompute() }
            .onChange(of: allBudgets)      { _, _ in recompute() }
            .onChange(of: selectedMonth)   { _, _ in recompute() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await sync.syncAll(modelContext: modelContext) }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .networkRestored)) { _ in
                Task { await sync.syncAll(modelContext: modelContext) }
            }
        }
    }

    // MARK: - Single-pass recompute

    private func recompute() {
        let cal = Calendar.current
        var inc = 0.0, exp = 0.0
        var catMap: [String: (name: String, icon: String, color: String?, total: Double)] = [:]
        var spending: [UUID: Double] = [:]
        var recent: [LocalTransaction] = []

        for tx in allTransactions {
            guard cal.isDate(tx.transactionDate, equalTo: selectedMonth, toGranularity: .month) else { continue }
            if tx.type == "income" {
                inc += tx.amount
            } else {
                exp += tx.amount
                let key = tx.categoryId?.uuidString ?? tx.categoryName ?? "other"
                let ex = catMap[key]
                catMap[key] = (
                    name: ex?.name ?? tx.categoryName ?? "Other",
                    icon: ex?.icon ?? tx.categoryIcon ?? "💸",
                    color: ex?.color ?? tx.categoryColor,
                    total: (ex?.total ?? 0) + tx.amount
                )
                if let cid = tx.categoryId { spending[cid, default: 0] += tx.amount }
            }
            if recent.count < 7 { recent.append(tx) }
        }

        monthlyIncome  = inc
        monthlyExpense = exp
        recentTransactions = recent
        spendingByCategoryId = spending

        let sorted = catMap.values.sorted { $0.total > $1.total }.prefix(5)
        let total  = sorted.reduce(0) { $0 + $1.total }
        let palette: [Color] = [.blue, .indigo, .purple, .pink, .orange]
        spendingItems = sorted.enumerated().map { i, item in
            CategorySpending(
                id: item.name, name: item.name, icon: item.icon,
                color: item.color.map { Color(hex: $0) } ?? palette[i % palette.count],
                amount: item.total,
                percentage: total > 0 ? item.total / total * 100 : 0
            )
        }

        currentBudgets = allBudgets.filter {
            cal.isDate($0.month, equalTo: selectedMonth, toGranularity: .month)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if !sync.isOnline {
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
        .cardBackground()
    }
}
