import SwiftUI
import SwiftData

@MainActor
final class TransactionViewModel: ObservableObject {

    // MARK: - Published state (read-only outside this class)

    @Published var selectedMonth: Date
    @Published private(set) var loadedTxs:      [LocalTransaction] = []
    @Published private(set) var isLoadingMore   = false
    @Published private(set) var isLoadingDateTxs = false
    @Published private(set) var hasMore         = true
    @Published private(set) var periodIncome:   Double = 0
    @Published private(set) var periodExpense:  Double = 0
    @Published private(set) var dailyData:      [Date: (income: Double, expense: Double)] = [:]
    @Published private(set) var groupedAll:     [(Date, [LocalTransaction])] = []
    @Published private(set) var groupedIncome:  [(Date, [LocalTransaction])] = []
    @Published private(set) var groupedExpense: [(Date, [LocalTransaction])] = []
    @Published var errorMsg: String?

    // MARK: - Private internals

    private var loadedIds: Set<UUID> = []
    private var serverPage = 0
    private let pageSize = 10
    private let client = SupabaseService.shared.client

    // MARK: - Init

    init() {
        selectedMonth = TransactionDateRange.monthStart(for: Date())
    }

    // MARK: - Computed helpers

    var currentMonthStart: Date {
        TransactionDateRange.monthStart(for: Date())
    }

    var isOnCurrentMonth: Bool {
        Calendar.current.isDate(selectedMonth, equalTo: Date(), toGranularity: .month)
    }

    // MARK: - Public API

    func jumpToToday() {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedMonth = currentMonthStart
        }
    }

    func resetAndLoad(in ctx: ModelContext) {
        loadedTxs = []; loadedIds = []
        groupedAll = []; groupedIncome = []; groupedExpense = []
        periodIncome = 0; periodExpense = 0
        dailyData = [:]; serverPage = 0; hasMore = true
        Task {
            async let t: Void = fetchPeriodTotals(in: ctx)
            async let m: Void = loadMore(in: ctx)
            async let i: Void = fetchIncome(in: ctx)
            _ = await (t, m, i)
        }
    }

    func loadMore(in ctx: ModelContext) async {
        guard hasMore, !isLoadingMore else { return }
        guard SyncManager.shared.isOnline else {
            if loadedTxs.isEmpty { fallbackFromCache(in: ctx) }
            hasMore = false
            return
        }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let (startStr, endStr) = periodRangeStrings()
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
            upsert(remote, in: ctx)
            serverPage += 1
            if remote.count < pageSize { hasMore = false }
        } catch {
            if loadedTxs.isEmpty { fallbackFromCache(in: ctx) }
            hasMore = false
            if SyncManager.shared.isOnline { errorMsg = error.localizedDescription }
        }
    }

    func ensureDateLoaded(_ date: Date, in ctx: ModelContext) async {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }

        let alreadyHave = loadedTxs.contains { $0.transactionDate >= start && $0.transactionDate < end }
        let dayHasData  = (dailyData[start]?.income ?? 0) + (dailyData[start]?.expense ?? 0) > 0
        guard !alreadyHave && dayHasData else { return }

        isLoadingDateTxs = true
        defer { isLoadingDateTxs = false }

        let startStr = TransactionDateRange.apiDateString(from: start)
        let endStr   = TransactionDateRange.apiDateString(from: end)

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
            upsert(remote, in: ctx)
        } catch {
            let desc = FetchDescriptor<LocalTransaction>(
                predicate: #Predicate<LocalTransaction> { $0.transactionDate >= start && $0.transactionDate < end },
                sortBy: [SortDescriptor(\.transactionDate, order: .reverse)]
            )
            let local = (try? ctx.fetch(desc)) ?? []
            for tx in local where !loadedIds.contains(tx.serverId) {
                loadedTxs.append(tx); loadedIds.insert(tx.serverId)
            }
            recomputeGrouped()
        }
    }

    func deleteTx(_ tx: LocalTransaction, in ctx: ModelContext) async {
        let wallets = (try? ctx.fetch(FetchDescriptor<LocalWallet>())) ?? []
        let wallet  = wallets.first { $0.serverId == tx.walletId }
        do {
            try await TransactionService.shared.delete(tx, wallet: wallet, in: ctx)
            loadedTxs.removeAll { $0.serverId == tx.serverId }
            recomputeGrouped()
            Task { await fetchPeriodTotals(in: ctx) }
        } catch { errorMsg = error.localizedDescription }
    }

    // MARK: - Private fetch helpers

    private func fetchPeriodTotals(in ctx: ModelContext) async {
        let (startStr, endStr) = periodRangeStrings()
        do {
            let userId = try await client.auth.session.user.id
            let records: [TransactionTotalRecord] = try await client
                .from("transactions")
                .select("type,amount,transaction_date,transfer_pair_id")
                .eq("user_id", value: userId)
                .gte("transaction_date", value: startStr)
                .lt("transaction_date",  value: endStr)
                .execute().value
            applyPeriodTotals(TransactionPeriodTotalsCalculator.calculate(from: records))
        } catch {
            guard let range = periodDateRange() else { return }
            let start = range.start
            let end = range.end
            let local = (try? ctx.fetch(FetchDescriptor<LocalTransaction>(
                predicate: #Predicate { $0.transactionDate >= start && $0.transactionDate < end }
            ))) ?? []
            applyPeriodTotals(TransactionPeriodTotalsCalculator.calculate(from: local))
        }
    }

    private func fetchIncome(in ctx: ModelContext) async {
        guard SyncManager.shared.isOnline else { return }
        let (startStr, endStr) = periodRangeStrings()
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
            upsert(remote, in: ctx)
        } catch { /* silently ignored — loadMore handles error state */ }
    }

    // MARK: - Private data helpers

    private func recomputeGrouped() {
        let grouped = TransactionGroupingCalculator.group(loadedTxs)
        groupedAll = grouped.all
        groupedIncome = grouped.income
        groupedExpense = grouped.expense
    }

    private func upsert(_ remotes: [RemoteTransaction], in ctx: ModelContext) {
        guard !remotes.isEmpty else { return }
        guard let range = periodDateRange() else { return }
        let start = range.start
        let end = range.end
        let existing = (try? ctx.fetch(FetchDescriptor<LocalTransaction>(
            predicate: #Predicate { $0.transactionDate >= start && $0.transactionDate < end }
        ))) ?? []
        let localMap = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })
        for r in remotes {
            if let local = localMap[r.id] {
                local.update(from: r)
                if !loadedIds.contains(r.id) { loadedTxs.append(local); loadedIds.insert(r.id) }
            } else {
                let local = LocalTransaction(from: r)
                ctx.insert(local)
                loadedTxs.append(local); loadedIds.insert(r.id)
            }
        }
        try? ctx.save()
        recomputeGrouped()
    }

    private func fallbackFromCache(in ctx: ModelContext) {
        guard let range = periodDateRange() else { return }
        let all = (try? ctx.fetch(
            FetchDescriptor<LocalTransaction>(sortBy: [SortDescriptor(\.transactionDate, order: .reverse)])
        )) ?? []
        loadedTxs = all.filter { $0.transactionDate >= range.start && $0.transactionDate < range.end }
        recomputeGrouped()
    }

    private func applyPeriodTotals(_ totals: TransactionPeriodTotals) {
        periodIncome = totals.income
        periodExpense = totals.expense
        dailyData = totals.dailyData
    }

    private func periodRangeStrings() -> (String, String) {
        TransactionDateRange.monthRangeStrings(for: selectedMonth)
    }

    private func periodDateRange() -> (start: Date, end: Date)? {
        TransactionDateRange.monthRange(for: selectedMonth)
    }
}
