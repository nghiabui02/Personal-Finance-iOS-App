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
        guard isOnline, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            // Fetch reference data in parallel
            async let walletsTask: [RemoteWallet] = client.from("wallets").select().execute().value
            async let categoriesTask: [RemoteCategory] = client.from("categories").select().execute().value
            let (wallets, categories) = try await (walletsTask, categoriesTask)

            upsertWallets(wallets, in: modelContext)
            upsertCategories(categories, in: modelContext)

            let categoryMap = Dictionary(uniqueKeysWithValues: categories.map {
                ($0.id, (name: $0.name, icon: $0.icon, color: $0.color))
            })
            let walletMap = Dictionary(uniqueKeysWithValues: wallets.map { ($0.id, $0.name) })

            // Fetch transactions (last 3 months) and budgets in parallel
            async let txTask = fetchTransactions(months: 3)
            async let budgetsTask = fetchBudgets(months: 2)
            let (transactions, budgets) = try await (txTask, budgetsTask)

            upsertTransactions(transactions, walletMap: walletMap, categoryMap: categoryMap, in: modelContext)
            upsertBudgets(budgets, categoryMap: categoryMap, in: modelContext)

            try modelContext.save()
            lastSyncDate = Date()
        } catch is CancellationError {
            // Task cancelled by SwiftUI lifecycle — not a real error
        } catch {
            syncError = error.localizedDescription
            print("[SyncManager] error: \(error)")
        }
    }

    // MARK: - Remote fetch

    private func fetchTransactions(months: Int) async throws -> [RemoteTransaction] {
        let since = Calendar.current.date(byAdding: .month, value: -months, to: Date())!
        return try await client
            .from("transactions")
            .select()
            .gte("transaction_date", value: dateFormatter.string(from: since))
            .order("transaction_date", ascending: false)
            .execute()
            .value
    }

    private func fetchBudgets(months: Int) async throws -> [RemoteBudget] {
        let since = Calendar.current.date(byAdding: .month, value: -months, to: Date())!
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: since))!
        return try await client
            .from("budgets")
            .select()
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

    private func upsertTransactions(
        _ remotes: [RemoteTransaction],
        walletMap: [String: String],
        categoryMap: [String: (name: String, icon: String?, color: String?)],
        in ctx: ModelContext
    ) {
        let existing = (try? ctx.fetch(FetchDescriptor<LocalTransaction>())) ?? []
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })
        for r in remotes {
            let walletName = r.walletId.flatMap { walletMap[$0] } ?? "Unknown Wallet"
            let cat = r.categoryId.flatMap { categoryMap[$0] }
            if let local = map[r.id] {
                local.update(from: r, walletName: walletName,
                             categoryName: cat?.name, categoryIcon: cat?.icon, categoryColor: cat?.color)
            } else {
                ctx.insert(LocalTransaction(from: r, walletName: walletName,
                                            categoryName: cat?.name, categoryIcon: cat?.icon, categoryColor: cat?.color))
            }
        }
    }

    private func upsertBudgets(
        _ remotes: [RemoteBudget],
        categoryMap: [String: (name: String, icon: String?, color: String?)],
        in ctx: ModelContext
    ) {
        let existing = (try? ctx.fetch(FetchDescriptor<LocalBudget>())) ?? []
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })
        for r in remotes {
            let cat = r.categoryId.flatMap { categoryMap[$0] }
            let name = cat?.name ?? "Unknown"
            let icon = cat?.icon
            let color = cat?.color
            if let local = map[r.id] {
                local.update(from: r, categoryName: name, categoryIcon: icon, categoryColor: color)
            } else {
                ctx.insert(LocalBudget(from: r, categoryName: name, categoryIcon: icon, categoryColor: color))
            }
        }
    }
}

extension Notification.Name {
    static let networkRestored = Notification.Name("com.nghiabui.pf.networkRestored")
}
