import SwiftUI
import SwiftData
import Supabase

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var sync = SyncManager.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var loadedTxs: [LocalTransaction] = []
    @State private var serverPage = 0
    @State private var isLoadingMore = false
    @State private var hasMore = true
    @State private var loadedIds: Set<UUID> = []

    @State private var periodIncome:  Double = 0
    @State private var periodExpense: Double = 0
    @State private var dailyData: [Date: (income: Double, expense: Double)] = [:]

    @State private var groupedAll:     [(Date, [LocalTransaction])] = []
    @State private var groupedIncome:  [(Date, [LocalTransaction])] = []
    @State private var groupedExpense: [(Date, [LocalTransaction])] = []

    @State private var selectedMonth: Date = {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
    }()
    @State private var selectedDate: Date? = nil
    @State private var filterType: FilterType = .all
    @State private var showAdd = false
    @State private var editing: LocalTransaction?
    @State private var errorMsg: String?
    @State private var isLoadingDateTxs = false

    private let pageSize = 10
    private let client = SupabaseService.shared.client
    private let df: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    private var currentMonthStart: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
    }

    private var isOnCurrentMonth: Bool {
        Calendar.current.isDate(selectedMonth, equalTo: Date(), toGranularity: .month)
    }

    private var displayedIncome: Double {
        guard let date = selectedDate else { return periodIncome }
        return dailyData[Calendar.current.startOfDay(for: date)]?.income ?? 0
    }

    private var displayedExpense: Double {
        guard let date = selectedDate else { return periodExpense }
        return dailyData[Calendar.current.startOfDay(for: date)]?.expense ?? 0
    }

    private var displayedGroups: [(Date, [LocalTransaction])] {
        let base: [(Date, [LocalTransaction])]
        switch filterType {
        case .all:     base = groupedAll
        case .income:  base = groupedIncome
        case .expense: base = groupedExpense
        }
        guard let date = selectedDate else { return base }
        return base.filter { Calendar.current.isDate($0.0, inSameDayAs: date) }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                TransactionHeaderSection(
                    selectedMonth: $selectedMonth,
                    selectedDate: $selectedDate,
                    filterType: $filterType,
                    dailyData: dailyData,
                    income: displayedIncome,
                    expense: displayedExpense
                )
                TransactionListSection(
                    groups: displayedGroups,
                    isLoading: loadedTxs.isEmpty && (isLoadingMore || isLoadingDateTxs),
                    onTap: { editing = $0 },
                    onDelete: { await deleteTx($0) }
                )
                TransactionPaginationSection(
                    selectedDate: selectedDate,
                    hasMore: hasMore,
                    isLoadingMore: isLoadingMore,
                    count: loadedTxs.count,
                    onLoadMore: loadMore
                )
            }
            .listStyle(.grouped)
            .listSectionSpacing(8)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Transactions")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !isOnCurrentMonth {
                        Button("Today") { jumpToToday() }
                            .font(.subheadline)
                            .transition(.opacity)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isOnCurrentMonth)
            .refreshable { resetAndLoad() }
            .onChange(of: scenePhase)    { _, p in if p == .active { resetAndLoad() } }
            .onChange(of: selectedMonth) { _, _ in resetAndLoad() }
            .onChange(of: loadedTxs)    { _, _ in recomputeGrouped() }
            .onChange(of: selectedDate) { _, date in
                guard let date else { return }
                Task { await ensureDateLoaded(date) }
            }
            .onAppear {
                let current = currentMonthStart
                if selectedMonth != current {
                    selectedMonth = current
                } else if loadedTxs.isEmpty {
                    resetAndLoad()
                }
            }
            .sheet(isPresented: $showAdd) {
                AddEditTransactionView(transaction: nil, defaultDate: selectedDate)
            }
            .sheet(item: $editing) { tx in AddEditTransactionView(transaction: tx) }
            .errorAlert($errorMsg)
        }
    }

    // MARK: - Grouped cache

    private func recomputeGrouped() {
        let cal = Calendar.current
        var all: [Date: [LocalTransaction]] = [:]
        var inc: [Date: [LocalTransaction]] = [:]
        var exp: [Date: [LocalTransaction]] = [:]
        for tx in loadedTxs {
            let day = cal.startOfDay(for: tx.transactionDate)
            all[day, default: []].append(tx)
            if tx.type == "income" { inc[day, default: []].append(tx) }
            else                   { exp[day, default: []].append(tx) }
        }
        groupedAll     = all.sorted { $0.key > $1.key }
        groupedIncome  = inc.sorted { $0.key > $1.key }
        groupedExpense = exp.sorted { $0.key > $1.key }
    }

    // MARK: - Load & pagination

    private func resetAndLoad() {
        loadedTxs = []; loadedIds = []
        groupedAll = []; groupedIncome = []; groupedExpense = []
        periodIncome = 0; periodExpense = 0
        dailyData = [:]; selectedDate = nil
        serverPage = 0; hasMore = true
        Task {
            async let totals: Void = fetchPeriodTotals()
            async let more: Void = loadMore()
            async let income: Void = fetchIncomeForCurrentPeriod()
            _ = await (totals, more, income)
        }
    }

    private func fetchPeriodTotals() async {
        let (startStr, endStr) = periodRange()
        struct TotalRecord: Decodable {
            let type: String; let amount: Double; let transaction_date: String
        }
        do {
            let userId = try await client.auth.session.user.id
            let records: [TotalRecord] = try await client
                .from("transactions")
                .select("type,amount,transaction_date")
                .eq("user_id", value: userId)
                .gte("transaction_date", value: startStr)
                .lt("transaction_date",  value: endStr)
                .execute().value

            var inc = 0.0, exp = 0.0
            var daily: [Date: (income: Double, expense: Double)] = [:]
            let cal = Calendar.current
            for r in records {
                if r.type == "income" { inc += r.amount } else { exp += r.amount }
                if let date = df.date(from: r.transaction_date) {
                    let day = cal.startOfDay(for: date)
                    var d = daily[day] ?? (income: 0, expense: 0)
                    if r.type == "income" { d.income += r.amount } else { d.expense += r.amount }
                    daily[day] = d
                }
            }
            periodIncome = inc; periodExpense = exp; dailyData = daily
        } catch {
            guard let start = df.date(from: startStr), let end = df.date(from: endStr) else { return }
            let desc = FetchDescriptor<LocalTransaction>(
                predicate: #Predicate<LocalTransaction> { $0.transactionDate >= start && $0.transactionDate < end }
            )
            let local = (try? modelContext.fetch(desc)) ?? []
            periodIncome  = local.filter { $0.type == "income"  }.reduce(0) { $0 + $1.amount }
            periodExpense = local.filter { $0.type == "expense" }.reduce(0) { $0 + $1.amount }
            var daily: [Date: (income: Double, expense: Double)] = [:]
            let cal = Calendar.current
            for tx in local {
                let day = cal.startOfDay(for: tx.transactionDate)
                var d = daily[day] ?? (income: 0, expense: 0)
                if tx.type == "income" { d.income += tx.amount } else { d.expense += tx.amount }
                daily[day] = d
            }
            dailyData = daily
        }
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        guard sync.isOnline else {
            if loadedTxs.isEmpty { fallbackFromCache() }
            hasMore = false
            return
        }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let (startStr, endStr) = periodRange()
        let from = serverPage * pageSize
        let to   = from + pageSize - 1

        do {
            let userId = try await client.auth.session.user.id
            let remote: [RemoteTransaction] = try await client
                .from("transactions")
                .select("*, categories(id, name, icon, color), wallets(id, name)")
                .eq("user_id", value: userId)
                .gte("transaction_date", value: startStr)
                .lt("transaction_date",  value: endStr)
                .order("transaction_date", ascending: false)
                .order("updated_at", ascending: false)
                .range(from: from, to: to)
                .execute().value
            upsert(remote)
            serverPage += 1
            if remote.count < pageSize { hasMore = false }
        } catch {
            if loadedTxs.isEmpty { fallbackFromCache() }
            hasMore = false
            if sync.isOnline { errorMsg = error.localizedDescription }
        }
    }

    private func fetchIncomeForCurrentPeriod() async {
        guard sync.isOnline else { return }
        let (startStr, endStr) = periodRange()
        do {
            let userId = try await client.auth.session.user.id
            let remote: [RemoteTransaction] = try await client
                .from("transactions")
                .select("*, categories(id, name, icon, color), wallets(id, name)")
                .eq("user_id", value: userId)
                .eq("type", value: "income")
                .gte("transaction_date", value: startStr)
                .lt("transaction_date",  value: endStr)
                .order("transaction_date", ascending: false)
                .order("updated_at", ascending: false)
                .range(from: 0, to: 29)
                .execute().value
            upsert(remote)
        } catch { /* silently ignored — loadMore already handles the error state */ }
    }

    private func ensureDateLoaded(_ date: Date) async {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }

        let alreadyHaveData = loadedTxs.contains { tx in
            tx.transactionDate >= start && tx.transactionDate < end
        }
        let dayHasData = (dailyData[start]?.income ?? 0) + (dailyData[start]?.expense ?? 0) > 0
        guard !alreadyHaveData && dayHasData else { return }

        isLoadingDateTxs = true
        defer { isLoadingDateTxs = false }

        let startStr = df.string(from: start)
        let endStr   = df.string(from: end)

        do {
            let userId = try await client.auth.session.user.id
            let remote: [RemoteTransaction] = try await client
                .from("transactions")
                .select("*, categories(id, name, icon, color), wallets(id, name)")
                .eq("user_id", value: userId)
                .gte("transaction_date", value: startStr)
                .lt("transaction_date",  value: endStr)
                .order("transaction_date", ascending: false)
                .order("updated_at", ascending: false)
                .execute().value
            upsert(remote)
        } catch {
            let desc = FetchDescriptor<LocalTransaction>(
                predicate: #Predicate<LocalTransaction> { $0.transactionDate >= start && $0.transactionDate < end },
                sortBy: [SortDescriptor(\.transactionDate, order: .reverse)]
            )
            let local = (try? modelContext.fetch(desc)) ?? []
            for tx in local where !loadedIds.contains(tx.serverId) {
                loadedTxs.append(tx); loadedIds.insert(tx.serverId)
            }
        }
    }

    private func upsert(_ remotes: [RemoteTransaction]) {
        guard !remotes.isEmpty else { return }
        let (startStr, endStr) = periodRange()
        guard let start = df.date(from: startStr), let end = df.date(from: endStr) else { return }
        let desc = FetchDescriptor<LocalTransaction>(
            predicate: #Predicate<LocalTransaction> { $0.transactionDate >= start && $0.transactionDate < end }
        )
        let existing = (try? modelContext.fetch(desc)) ?? []
        let localMap = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })
        for r in remotes {
            if let local = localMap[r.id] {
                local.update(from: r)
                if !loadedIds.contains(r.id) { loadedTxs.append(local); loadedIds.insert(r.id) }
            } else {
                let local = LocalTransaction(from: r)
                modelContext.insert(local)
                loadedTxs.append(local); loadedIds.insert(r.id)
            }
        }
        try? modelContext.save()
    }

    private func fallbackFromCache() {
        let (startStr, endStr) = periodRange()
        guard let start = df.date(from: startStr), let end = df.date(from: endStr) else { return }
        let all = (try? modelContext.fetch(
            FetchDescriptor<LocalTransaction>(sortBy: [SortDescriptor(\.transactionDate, order: .reverse)])
        )) ?? []
        loadedTxs = all.filter { $0.transactionDate >= start && $0.transactionDate < end }
    }

    // MARK: - Helpers

    private func jumpToToday() {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedDate = nil
            selectedMonth = currentMonthStart
        }
    }

    private func periodRange() -> (String, String) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: selectedMonth)
        let start = cal.date(from: comps)!
        let end   = cal.date(byAdding: .month, value: 1, to: start)!
        return (df.string(from: start), df.string(from: end))
    }

    private func deleteTx(_ tx: LocalTransaction) async {
        let wallets = (try? modelContext.fetch(FetchDescriptor<LocalWallet>())) ?? []
        let wallet = wallets.first { $0.serverId == tx.walletId }
        do {
            try await TransactionService.shared.delete(tx, wallet: wallet, in: modelContext)
            loadedTxs.removeAll { $0.serverId == tx.serverId }
            Task { await fetchPeriodTotals() }
        } catch { errorMsg = error.localizedDescription }
    }
}
