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
    @Query private var debts: [LocalDebt]

    // Cached — computed once per month/data change, not on every render
    @State private var monthlyIncome:  Double = 0
    @State private var monthlyExpense: Double = 0
    @State private var recentTransactions: [LocalTransaction] = []
    @State private var spendingByCategoryId: [UUID: Double] = [:]
    @State private var spendingItems: [CategorySpending] = []
    @State private var currentBudgets: [LocalBudget] = []
    @State private var alerts: [DashboardAlert] = []
    @State private var quickAction: DashboardQuickAction?
    
    @State private var notificationSubscription: NSObjectProtocol?

    private var netBalance: Double { monthlyIncome - monthlyExpense }
    private let primaryCurrency = "VND"
    private var outstandingLent: Double {
        debts.filter { $0.type == "lend" && $0.status != "completed" }
            .reduce(0) { $0 + $1.remainingAmount }
    }
    private var outstandingBorrowed: Double {
        debts.filter { $0.type == "borrow" && $0.status != "completed" }
            .reduce(0) { $0 + $1.remainingAmount }
    }
    private var netWorth: Double {
        let cash = wallets.filter { $0.type != "credit" }.reduce(0) { $0 + $1.balance }
        let creditDebt = wallets.filter { $0.type == "credit" }.reduce(0) { $0 + $1.amountOwed }
        return cash + outstandingLent - creditDebt - outstandingBorrowed
    }

    // MARK: - View

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            dashboardScreen
        }
    }

    private var dashboardScreen: some View {
        dashboardBase
            .sheet(item: $quickAction) { action in
                switch action {
                case .transaction: AddEditTransactionView(transaction: nil)
                case .debt: AddEditDebtView(debt: nil)
                }
            }
            .refreshable { await sync.syncAll(modelContext: modelContext) }
            .onAppear {
                recompute()
                Task { @MainActor in await sync.syncAll(modelContext: modelContext) }
                guard notificationSubscription == nil else { return }
                notificationSubscription = NotificationCenter.default.addObserver(
                    forName: .networkRestored,
                    object: nil,
                    queue: .main
                ) { _ in
                    Task { @MainActor in await sync.syncAll(modelContext: modelContext) }
                }
            }
            .onChange(of: allTransactions) { _, _ in recompute() }
            .onChange(of: allBudgets)      { _, _ in recompute() }
            .onChange(of: wallets)         { _, _ in recompute() }
            .onChange(of: debts)           { _, _ in recompute() }
            .onChange(of: selectedMonth)   { _, _ in recompute() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { @MainActor in await sync.syncAll(modelContext: modelContext) }
                }
            }
            .onDisappear {
                if let subscription = notificationSubscription {
                    NotificationCenter.default.removeObserver(subscription)
                    notificationSubscription = nil
                }
            }
    }

    private var dashboardBase: some View {
        ScrollView {
            dashboardContent
        }
        .background(Color(.systemGroupedBackground))
        .gesture(monthSwipeGesture)
        .navigationTitle("Overview")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { statusIcon }
            ToolbarItem(placement: .topBarTrailing) { quickAddMenu }
        }
    }

    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) * 2, abs(horizontal) > 60 else { return }
                let delta = horizontal < 0 ? 1 : -1
                if let next = Calendar.current.date(byAdding: .month, value: delta, to: selectedMonth) {
                    withAnimation { selectedMonth = next }
                }
            }
    }

    private var quickAddMenu: some View {
        Menu {
            Button {
                quickAction = .transaction
            } label: {
                Label("Add Transaction", systemImage: "plus.circle")
            }
            Button {
                quickAction = .debt
            } label: {
                Label("Add Debt", systemImage: "person.crop.circle.badge.plus")
            }
        } label: {
            Image(systemName: "plus")
        }
    }

    private var dashboardContent: some View {
        VStack(spacing: 16) {
            MonthSelectorView(selectedMonth: $selectedMonth)

            if let err = sync.syncError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            OverviewCard(
                netBalance: netBalance,
                income: monthlyIncome,
                expense: monthlyExpense,
                currency: primaryCurrency
            )
            .padding(.horizontal)

            NetWorthCard(
                netWorth: netWorth,
                lent: outstandingLent,
                borrowed: outstandingBorrowed,
                currency: primaryCurrency
            )
            .padding(.horizontal)

            if !alerts.isEmpty {
                DashboardAlertsCard(alerts: alerts)
                    .padding(.horizontal)
            }

            SpendingChartView(
                items: spendingItems,
                total: monthlyExpense,
                currency: primaryCurrency
            )
            .padding(.horizontal)

            recentTransactionsSection

            BudgetProgressView(
                budgets: currentBudgets,
                spendingByCategoryId: spendingByCategoryId,
                currency: primaryCurrency
            )
            .padding(.horizontal)
        }
        .padding(.vertical)
    }

    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Transactions")
                .font(.headline)
                .padding(.horizontal)

            if recentTransactions.isEmpty && !sync.isSyncing {
                ContentUnavailableView(
                    "No Transactions",
                    systemImage: "tray",
                    description: Text("Pull down to refresh")
                )
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
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal)
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
            if !tx.isTransfer {
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
            }
            if recent.count < 6 { recent.append(tx) }
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

        var nextAlerts: [DashboardAlert] = []
        for budget in currentBudgets {
            let spent = budget.categoryId.map { spending[$0, default: 0] } ?? 0
            guard budget.amount > 0, spent >= budget.amount * 0.8 else { continue }
            let exceeded = spent > budget.amount
            nextAlerts.append(DashboardAlert(
                id: "budget-\(budget.serverId)",
                title: exceeded ? "Budget exceeded" : "Budget almost used",
                message: "\(budget.categoryName): \(spent.formatted(currency: primaryCurrency)) of \(budget.amount.formatted(currency: primaryCurrency))",
                symbol: exceeded ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill",
                color: exceeded ? .red : .orange,
                priority: exceeded ? 0 : 2
            ))
        }

        let today = cal.startOfDay(for: Date())
        let sevenDays = cal.date(byAdding: .day, value: 7, to: today)!
        for debt in debts where debt.status != "completed" {
            guard let due = debt.dueDate else { continue }
            let dueDay = cal.startOfDay(for: due)
            guard dueDay <= sevenDays else { continue }
            let overdue = dueDay < today
            nextAlerts.append(DashboardAlert(
                id: "debt-\(debt.serverId)",
                title: overdue ? "Debt overdue" : "Debt due soon",
                message: "\(debt.personName) · \(debt.remainingAmount.formatted(currency: primaryCurrency))",
                symbol: overdue ? "calendar.badge.exclamationmark" : "calendar.badge.clock",
                color: overdue ? .red : .orange,
                priority: overdue ? 1 : 3
            ))
        }
        alerts = Array(nextAlerts.sorted { $0.priority < $1.priority }.prefix(5))
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

private enum DashboardQuickAction: String, Identifiable {
    case transaction, debt
    var id: String { rawValue }
}

private struct DashboardAlert: Identifiable {
    let id: String
    let title: String
    let message: String
    let symbol: String
    let color: Color
    let priority: Int
}

private struct DashboardAlertsCard: View {
    let alerts: [DashboardAlert]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ALERTS")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .tracking(1)
            ForEach(alerts) { alert in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: alert.symbol)
                        .foregroundColor(alert.color)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.title).font(.subheadline.weight(.semibold))
                        Text(alert.message).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct NetWorthCard: View {
    let netWorth: Double
    let lent: Double
    let borrowed: Double
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NET WORTH")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .tracking(1)
            Text(netWorth.formatted(currency: currency))
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundColor(netWorth >= 0 ? .primary : .expense)
            HStack {
                Label(lent.formatted(currency: currency), systemImage: "arrow.up.right")
                    .foregroundColor(.lend)
                Spacer()
                Label(borrowed.formatted(currency: currency), systemImage: "arrow.down.left")
                    .foregroundColor(.borrow)
            }
            .font(.caption.weight(.medium))
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct OverviewCard: View {
    let netBalance: Double
    let income: Double
    let expense: Double
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("NET BALANCE")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .tracking(1)
                Text(netBalance.formatted(currency: currency))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundColor(netBalance >= 0 ? .income : .expense)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .padding()

            Divider()

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("INCOME")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .tracking(1)
                    Text("+\(income.formatted(currency: currency))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.income)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()

                VStack(alignment: .leading, spacing: 6) {
                    Text("EXPENSE")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .tracking(1)
                    Text(expense.formatted(currency: currency))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.expense)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
