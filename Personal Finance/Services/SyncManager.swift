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
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
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
            reconcile(LocalWallet.self, with: wallets, in: modelContext)
            reconcile(LocalCategory.self, with: categories, in: modelContext)

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
            reconcile(LocalDebt.self, with: debts, in: modelContext)
            reconcile(LocalSavingGoal.self, with: goals, in: modelContext)
            reconcile(LocalRecurringTransaction.self, with: recurring, in: modelContext)

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
            print("[SyncManager] error: \(Self.describe(error))")
            #endif
        }
    }

    #if DEBUG
    /// `localizedDescription` on a DecodingError says only "the data couldn't be read
    /// because it's missing" — it drops the coding path, which is the one thing that
    /// identifies the offending field.
    private static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return "\(error)" }
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map(\.stringValue).joined(separator: ".")
        }
        switch decoding {
        case let .keyNotFound(key, context):
            return "DecodingError.keyNotFound — missing key '\(key.stringValue)' at [\(path(context))]"
        case let .valueNotFound(type, context):
            return "DecodingError.valueNotFound — null for non-optional \(type) at [\(path(context))]"
        case let .typeMismatch(type, context):
            return "DecodingError.typeMismatch — expected \(type) at [\(path(context))]"
        case let .dataCorrupted(context):
            return "DecodingError.dataCorrupted at [\(path(context))]: \(context.debugDescription)"
        @unknown default:
            return "DecodingError (unknown): \(decoding)"
        }
    }
    #endif

    // MARK: - Remote fetch

    private func fetchTransactions(userId: UUID, months: Int) async throws -> [RemoteTransaction] {
        let since = Calendar.current.date(byAdding: .month, value: -months, to: Date())!
        return try await client
            .from("transactions")
            .select("*, categories(id, name, icon, color), wallets(id, name)")
            .eq("user_id", value: userId)
            .gte("transaction_date", value: LedgerDate.dayFormatter.string(from: since))
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
            .gte("month", value: LedgerDate.dayFormatter.string(from: start))
            .execute()
            .value
    }

    // MARK: - SwiftData upsert

    /// Makes the local copy of a fully-fetched table match the server exactly.
    ///
    /// The remote set is the whole table, so anything local that is not in it was
    /// deleted elsewhere and is removed here. Tables synced by date window
    /// (transactions, budgets) cannot use this — their remote set is a slice, and
    /// pruning against it would delete rows outside the window.
    private func reconcile<Model: ServerBacked>(
        _ type: Model.Type,
        with remotes: [Model.Remote],
        in ctx: ModelContext
    ) {
        let remoteIds = Set(remotes.map(Model.remoteId))
        let existing = (try? ctx.fetch(FetchDescriptor<Model>())) ?? []
        let map = Dictionary(existing.map { ($0.serverId, $0) }, uniquingKeysWith: { first, _ in first })

        for local in existing where !remoteIds.contains(local.serverId) {
            ctx.delete(local)
        }
        for remote in remotes {
            if let local = map[Model.remoteId(remote)] { local.update(from: remote) }
            else { ctx.insert(Model(from: remote)) }
        }
    }

    private func upsertTransactions(_ remotes: [RemoteTransaction], since: Date, in ctx: ModelContext) {
        let remoteIds = Set(remotes.map { $0.id })
        let desc = FetchDescriptor<LocalTransaction>(
            predicate: #Predicate<LocalTransaction> { $0.transactionDate >= since }
        )
        let existing = (try? ctx.fetch(desc)) ?? []
        let map = Dictionary(existing.map { ($0.serverId, $0) }, uniquingKeysWith: { first, _ in first })
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
        let map = Dictionary(existing.map { ($0.serverId, $0) }, uniquingKeysWith: { first, _ in first })
        for local in existing where !remoteIds.contains(local.serverId) {
            ctx.delete(local)
        }
        for r in remotes {
            if let local = map[r.id] { local.update(from: r) }
            else { ctx.insert(LocalBudget(from: r)) }
        }
    }



}

extension Notification.Name {
    static let networkRestored = Notification.Name("com.nghiabui.pf.networkRestored")
}
