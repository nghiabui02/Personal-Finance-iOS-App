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

            // Wallets + Categories in parallel (categories needs userId for OR filter)
            async let walletsTask: [RemoteWallet] = client
                .from("wallets")
                .select()
                .execute()
                .value
            async let categoriesTask: [RemoteCategory] = client
                .from("categories")
                .select()
                .or("user_id.is.null,user_id.eq.\(userId)")
                .execute()
                .value
            let (wallets, categories) = try await (walletsTask, categoriesTask)

            upsertWallets(wallets, in: modelContext)
            upsertCategories(categories, in: modelContext)

            // Transactions (JOIN) + Budgets (JOIN) in parallel
            async let txTask = fetchTransactions(months: 3)
            async let budgetsTask = fetchBudgets(months: 2)
            let (transactions, budgets) = try await (txTask, budgetsTask)

            upsertTransactions(transactions, in: modelContext)
            upsertBudgets(budgets, in: modelContext)

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
            print("[SyncManager] error: \(error)")
        }
    }

    // MARK: - Remote fetch

    private func fetchTransactions(months: Int) async throws -> [RemoteTransaction] {
        let since = Calendar.current.date(byAdding: .month, value: -months, to: Date())!
        return try await client
            .from("transactions")
            .select("*, categories(id, name, icon, color), wallets(id, name)")
            .gte("transaction_date", value: dateFormatter.string(from: since))
            .order("transaction_date", ascending: false)
            .execute()
            .value
    }

    private func fetchBudgets(months: Int) async throws -> [RemoteBudget] {
        let since = Calendar.current.date(byAdding: .month, value: -months, to: Date())!
        let start = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: since)
        )!
        return try await client
            .from("budgets")
            .select("*, categories(id, name, icon, color)")
            .gte("month", value: dateFormatter.string(from: start))
            .execute()
            .value
    }

    // MARK: - SwiftData upsert

    private func upsertWallets(_ remotes: [RemoteWallet], in ctx: ModelContext) {
        let existing = (try? ctx.fetch(FetchDescriptor<LocalWallet>())) ?? []
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })
        for r in remotes {
            if let local = map[r.id] { local.update(from: r) }
            else { ctx.insert(LocalWallet(from: r)) }
        }
    }

    private func upsertCategories(_ remotes: [RemoteCategory], in ctx: ModelContext) {
        let existing = (try? ctx.fetch(FetchDescriptor<LocalCategory>())) ?? []
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })
        for r in remotes {
            if let local = map[r.id] { local.update(from: r) }
            else { ctx.insert(LocalCategory(from: r)) }
        }
    }

    private func upsertTransactions(_ remotes: [RemoteTransaction], in ctx: ModelContext) {
        let existing = (try? ctx.fetch(FetchDescriptor<LocalTransaction>())) ?? []
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })
        for r in remotes {
            if let local = map[r.id] { local.update(from: r) }
            else { ctx.insert(LocalTransaction(from: r)) }
        }
    }

    private func upsertBudgets(_ remotes: [RemoteBudget], in ctx: ModelContext) {
        let existing = (try? ctx.fetch(FetchDescriptor<LocalBudget>())) ?? []
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })
        for r in remotes {
            if let local = map[r.id] { local.update(from: r) }
            else { ctx.insert(LocalBudget(from: r)) }
        }
    }
}

extension Notification.Name {
    static let networkRestored = Notification.Name("com.nghiabui.pf.networkRestored")
}
