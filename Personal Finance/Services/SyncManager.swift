import Foundation
import Network
import SwiftData
import Supabase

@MainActor
final class SyncManager: ObservableObject {
    static let shared = SyncManager()

    @Published var isOnline = true
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.nghiabui.pf.network")
    private let client = SupabaseService.shared.client
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        return f
    }()

    private init() {
        monitor.pathUpdateHandler = { path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = connected
                if wasOffline && connected {
                    NotificationCenter.default.post(name: .networkRestored, object: nil)
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    func syncAll(modelContext: ModelContext) async {
        guard !isSyncing else { return }
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }

        do {
            let userId = try await client.auth.session.user.id
            LocalDataStore.prepareForAuthenticatedUser(userId, in: modelContext)

            async let walletsTask: [RemoteWallet] = client.from("wallets")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value
            async let categoriesTask: [RemoteCategory] = client.from("categories").select()
                .or("user_id.is.null,user_id.eq.\(userId)").execute().value
            let (wallets, categories) = try await (walletsTask, categoriesTask)
            upsertWallets(wallets, in: modelContext)
            upsertCategories(categories, in: modelContext)

            let txSince  = Calendar.current.date(byAdding: .month, value: -12, to: Date())!
            let budSince = Calendar.current.date(
                from: Calendar.current.dateComponents([.year, .month],
                    from: Calendar.current.date(byAdding: .month, value: -12, to: Date())!))!

            async let txTask = fetchTransactions(userId: userId, months: 12)
            async let budgetsTask = fetchBudgets(userId: userId, months: 12)
            async let debtsTask: [RemoteDebt] = client.from("debts")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value
            async let goalsTask: [RemoteSavingGoal] = client.from("saving_goals")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value
            async let recurringTask: [RemoteRecurringTransaction] = client
                .from("recurring_transactions")
                .select("*, categories(id, name, icon, color), wallets(id, name)")
                .eq("user_id", value: userId)
                .execute().value
            let (transactions, budgets, debts, goals, recurring) = try await (txTask, budgetsTask, debtsTask, goalsTask, recurringTask)

            upsertTransactions(transactions, since: txSince, in: modelContext)
            upsertBudgets(budgets, since: budSince, in: modelContext)
            upsertDebts(debts, in: modelContext)
            upsertSavingGoals(goals, in: modelContext)
            upsertRecurring(recurring, in: modelContext)

            try modelContext.save()
            lastSyncDate = Date()
        } catch is CancellationError {
            // Swift task cancellation — not a real error
        } catch let urlError as URLError where urlError.code == .cancelled {
            // URLSession task cancelled (app lifecycle transition) — not a real error
        } catch {
            if !isOnline {
                syncError = "No internet connection. Data may be outdated."
            } else {
                syncError = error.localizedDescription
            }
            #if DEBUG
            print("[SyncManager] error: \(error)")
            #endif
        }
    }

    // MARK: - Remote fetch

    private func fetchTransactions(userId: UUID, months: Int) async throws -> [RemoteTransaction] {
        let since = Calendar.current.date(byAdding: .month, value: -months, to: Date())!
        return try await client
            .from("transactions")
            .select("*, categories(id, name, icon, color), wallets(id, name)")
            .eq("user_id", value: userId)
            .gte("transaction_date", value: dateFormatter.string(from: since))
            .order("transaction_date", ascending: false)
            .order("updated_at", ascending: false)
            .execute()
            .value
    }

    private func fetchBudgets(userId: UUID, months: Int) async throws -> [RemoteBudget] {
        let since = Calendar.current.date(byAdding: .month, value: -months, to: Date())!
        let start = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: since)
        )!
        return try await client
            .from("budgets")
            .select("*, categories(id, name, icon, color)")
            .eq("user_id", value: userId)
            .gte("month", value: dateFormatter.string(from: start))
            .execute()
            .value
    }

    // MARK: - SwiftData upsert

    private func upsertWallets(_ remotes: [RemoteWallet], in ctx: ModelContext) {
        let walletIds = remotes.map { $0.id }
        let predicate = #Predicate<LocalWallet> { wallet in
            walletIds.contains(wallet.serverId)
        }
        let desc = FetchDescriptor<LocalWallet>(predicate: predicate)
        let existing = (try? ctx.fetch(desc)) ?? []
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })
        for r in remotes {
            if let local = map[r.id] { local.update(from: r) }
            else { ctx.insert(LocalWallet(from: r)) }
        }
    }

    private func upsertCategories(_ remotes: [RemoteCategory], in ctx: ModelContext) {
        let categoryIds = remotes.map { $0.id }
        let predicate = #Predicate<LocalCategory> { category in
            categoryIds.contains(category.serverId)
        }
        let desc = FetchDescriptor<LocalCategory>(predicate: predicate)
        let existing = (try? ctx.fetch(desc)) ?? []
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })
        for r in remotes {
            if let local = map[r.id] { local.update(from: r) }
            else { ctx.insert(LocalCategory(from: r)) }
        }
    }

    private func upsertTransactions(_ remotes: [RemoteTransaction], since: Date, in ctx: ModelContext) {
        let remoteIds = Set(remotes.map { $0.id })
        let desc = FetchDescriptor<LocalTransaction>(
            predicate: #Predicate<LocalTransaction> { $0.transactionDate >= since }
        )
        let existing = (try? ctx.fetch(desc)) ?? []
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })
        for local in existing where !remoteIds.contains(local.serverId) {
            ctx.delete(local)
        }
        for r in remotes {
            if let local = map[r.id] { local.update(from: r) }
            else { ctx.insert(LocalTransaction(from: r)) }
        }
    }

    private func upsertBudgets(_ remotes: [RemoteBudget], since: Date, in ctx: ModelContext) {
        let remoteIds = Set(remotes.map { $0.id })
        let desc = FetchDescriptor<LocalBudget>(
            predicate: #Predicate<LocalBudget> { $0.month >= since }
        )
        let existing = (try? ctx.fetch(desc)) ?? []
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })
        for local in existing where !remoteIds.contains(local.serverId) {
            ctx.delete(local)
        }
        for r in remotes {
            if let local = map[r.id] { local.update(from: r) }
            else { ctx.insert(LocalBudget(from: r)) }
        }
    }

    private func upsertDebts(_ remotes: [RemoteDebt], in ctx: ModelContext) {
        let debtIds = remotes.map { $0.id }
        let predicate = #Predicate<LocalDebt> { debt in
            debtIds.contains(debt.serverId)
        }
        let desc = FetchDescriptor<LocalDebt>(predicate: predicate)
        let existing = (try? ctx.fetch(desc)) ?? []
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })
        for r in remotes {
            if let local = map[r.id] { local.update(from: r) }
            else { ctx.insert(LocalDebt(from: r)) }
        }
    }

    private func upsertSavingGoals(_ remotes: [RemoteSavingGoal], in ctx: ModelContext) {
        let goalIds = remotes.map { $0.id }
        let predicate = #Predicate<LocalSavingGoal> { goal in
            goalIds.contains(goal.serverId)
        }
        let desc = FetchDescriptor<LocalSavingGoal>(predicate: predicate)
        let existing = (try? ctx.fetch(desc)) ?? []
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })
        for r in remotes {
            if let local = map[r.id] { local.update(from: r) }
            else { ctx.insert(LocalSavingGoal(from: r)) }
        }
    }

    private func upsertRecurring(_ remotes: [RemoteRecurringTransaction], in ctx: ModelContext) {
        let recurringIds = remotes.map { $0.id }
        let predicate = #Predicate<LocalRecurringTransaction> { rec in
            recurringIds.contains(rec.serverId)
        }
        let desc = FetchDescriptor<LocalRecurringTransaction>(predicate: predicate)
        let existing = (try? ctx.fetch(desc)) ?? []
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })
        for r in remotes {
            if let local = map[r.id] { local.update(from: r) }
            else { ctx.insert(LocalRecurringTransaction(from: r)) }
        }
    }
}

extension Notification.Name {
    static let networkRestored = Notification.Name("com.nghiabui.pf.networkRestored")
}
