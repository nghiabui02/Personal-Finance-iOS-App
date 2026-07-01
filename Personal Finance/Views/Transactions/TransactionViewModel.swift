import SwiftUI
import SwiftData

private let _vmDF: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
    return f
}()

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
        let cal = Calendar.current
        selectedMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
    }

    // MARK: - Computed helpers

    var currentMonthStart: Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
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

        let startStr = _vmDF.string(from: start)
        let endStr   = _vmDF.string(from: end)

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
        let (startStr, endStr) = periodRange()
        struct TotalRecord: Decodable {
            let type: String, amount: Double, transaction_date: String
            let transfer_pair_id: UUID?
        }
        do {
            let userId = try await client.auth.session.user.id
            let records: [TotalRecord] = try await client
                .from("transactions")
                .select("type,amount,transaction_date,transfer_pair_id")
                .eq("user_id", value: userId)
                .gte("transaction_date", value: startStr)
                .lt("transaction_date",  value: endStr)
                .execute().value
            var inc = 0.0, exp = 0.0
            var daily: [Date: (income: Double, expense: Double)] = [:]
            for r in records {
                guard r.transfer_pair_id == nil else { continue }
                if r.type == "income" { inc += r.amount } else { exp += r.amount }
                if let date = _vmDF.date(from: r.transaction_date) {
                    let day = Calendar.current.startOfDay(for: date)
                    var d = daily[day] ?? (0, 0)
                    if r.type == "income" { d.income += r.amount } else { d.expense += r.amount }
                    daily[day] = d
                }
            }
            periodIncome = inc; periodExpense = exp; dailyData = daily
        } catch {
            guard let start = _vmDF.date(from: startStr),
                  let end   = _vmDF.date(from: endStr) else { return }
            let local = (try? ctx.fetch(FetchDescriptor<LocalTransaction>(
                predicate: #Predicate { $0.transactionDate >= start && $0.transactionDate < end }
            ))) ?? []
            let reportable = local.filter { !$0.isTransfer }
            periodIncome  = reportable.filter { $0.type == "income"  }.reduce(0) { $0 + $1.amount }
            periodExpense = reportable.filter { $0.type == "expense" }.reduce(0) { $0 + $1.amount }
            var daily: [Date: (income: Double, expense: Double)] = [:]
            for tx in reportable {
                let day = Calendar.current.startOfDay(for: tx.transactionDate)
                var d = daily[day] ?? (0, 0)
                if tx.type == "income" { d.income += tx.amount } else { d.expense += tx.amount }
                daily[day] = d
            }
            dailyData = daily
        }
    }

    private func fetchIncome(in ctx: ModelContext) async {
        guard SyncManager.shared.isOnline else { return }
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
            upsert(remote, in: ctx)
        } catch { /* silently ignored — loadMore handles error state */ }
    }

    // MARK: - Private data helpers

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

    private func upsert(_ remotes: [RemoteTransaction], in ctx: ModelContext) {
        guard !remotes.isEmpty else { return }
        let (startStr, endStr) = periodRange()
        guard let start = _vmDF.date(from: startStr),
              let end   = _vmDF.date(from: endStr) else { return }
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
        let (startStr, endStr) = periodRange()
        guard let start = _vmDF.date(from: startStr),
              let end   = _vmDF.date(from: endStr) else { return }
        let all = (try? ctx.fetch(
            FetchDescriptor<LocalTransaction>(sortBy: [SortDescriptor(\.transactionDate, order: .reverse)])
        )) ?? []
        loadedTxs = all.filter { $0.transactionDate >= start && $0.transactionDate < end }
        recomputeGrouped()
    }

    private func periodRange() -> (String, String) {
        let cal   = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth))!
        let end   = cal.date(byAdding: .month, value: 1, to: start)!
        return (_vmDF.string(from: start), _vmDF.string(from: end))
    }
}
