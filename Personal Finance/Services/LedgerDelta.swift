import Foundation
import Supabase
import SwiftData

/// Where the last sync of one account left off.
///
/// `since` is the server's clock (`sync_clock()`) when the last download started, so the
/// device clock never decides what counts as new. Each delta re-reads `overlap` before
/// it: `now()` is fixed when a database transaction starts, so a write can commit after
/// the download began while carrying an older stamp.
/// ponytail: assumes no write transaction runs longer than `overlap`; the daily full
/// sync repairs anything a longer one hides. Commit long jobs per user if that changes.
struct SyncCursor: Codable {
    var since: Date
    var lastFullSync: Date

    static let overlap: TimeInterval = 5 * 60
    /// A full download still runs daily: it repairs anything a delta cannot see, such as
    /// a renamed catalog category, and keeps the deletion log short-lived.
    static let fullSyncInterval: TimeInterval = 24 * 60 * 60

    private static let keyPrefix = "pf_sync_cursor_"

    var isDueForFullSync: Bool { Date().timeIntervalSince(lastFullSync) > Self.fullSyncInterval }

    static func load(for userId: UUID) -> SyncCursor? {
        guard let data = UserDefaults.standard.data(forKey: key(for: userId)) else { return nil }
        return try? JSONDecoder().decode(SyncCursor.self, from: data)
    }

    func save(for userId: UUID) throws {
        UserDefaults.standard.set(try JSONEncoder().encode(self), forKey: Self.key(for: userId))
    }

    /// Called whenever the local store is emptied: a cursor without the rows it
    /// describes would make the next delta skip everything older than it.
    static func resetAll() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private static func key(for userId: UUID) -> String { keyPrefix + userId.uuidString.lowercased() }
}

/// A row the database logged in `sync_deletions` when it was removed.
struct SyncDeletion: Decodable, Identifiable {
    let id: UUID
    let table: String

    enum CodingKeys: String, CodingKey {
        case id = "row_id"
        case table = "table_name"
    }
}

/// Everything that changed on the server since a cursor.
struct LedgerChanges {
    let wallets: [RemoteWallet]
    let categories: [RemoteCategory]
    let transactions: [RemoteTransaction]
    let budgets: [RemoteBudget]
    let debts: [RemoteDebt]
    let goals: [RemoteSavingGoal]
    let recurring: [RemoteRecurringTransaction]
    let deletions: [SyncDeletion]
    let snapshots: [RemoteNetWorthSnapshot]

    static func fetch(client: PostgrestClient, userId: UUID, since cursor: Date) async throws -> Self {
        let since = cursor.addingTimeInterval(-SyncCursor.overlap)
            .formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        async let wallets: [RemoteWallet] = client.readChangedRows("wallets", userId: userId, since: since)
        async let categories: [RemoteCategory] = client.readChangedRows(
            "user_categories", columns: CategoryProjection.membership, userId: userId, since: since)
        async let transactions: [RemoteTransaction] = client.readChangedRows(
            "transactions", columns: CategoryProjection.withWallet, userId: userId, since: since)
        async let budgets: [RemoteBudget] = client.readChangedRows(
            "budgets", columns: CategoryProjection.withCategory, userId: userId, since: since)
        async let debts: [RemoteDebt] = client.readChangedRows("debts", userId: userId, since: since)
        async let goals: [RemoteSavingGoal] = client.readChangedRows("saving_goals", userId: userId, since: since)
        async let recurring: [RemoteRecurringTransaction] = client.readChangedRows(
            "recurring_transactions", columns: CategoryProjection.withWallet, userId: userId, since: since)
        async let deletions: [SyncDeletion] = client.readRows(idColumn: "row_id") {
            client.from("sync_deletions").select().eq("user_id", value: userId).gt("deleted_at", value: since)
        }
        async let snapshots = client.readNetWorthHistory(userId: userId)
        return try await Self(
            wallets: wallets, categories: categories, transactions: transactions, budgets: budgets,
            debts: debts, goals: goals, recurring: recurring, deletions: deletions, snapshots: snapshots)
    }

    @MainActor
    func apply(in context: ModelContext) throws {
        do {
            try upsert(LocalWallet.self, wallets, in: context)
            try upsert(LocalCategory.self, categories, in: context)
            try upsert(LocalTransaction.self, transactions, in: context)
            try upsert(LocalBudget.self, budgets, in: context)
            try upsert(LocalDebt.self, debts, in: context)
            try upsert(LocalSavingGoal.self, goals, in: context)
            try upsert(LocalRecurringTransaction.self, recurring, in: context)
            try removeDeleted(in: context)
            try refreshWalletNames(in: context)
            try refreshCategoryDetails(in: context)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    @MainActor
    private func upsert<Model: ServerBacked>(
        _ type: Model.Type, _ remotes: [Model.Remote], in context: ModelContext
    ) throws {
        guard !remotes.isEmpty else { return }
        let existing = try context.fetch(Model.withServerIds(remotes.map(Model.remoteId)))
        let byId = Dictionary(existing.map { ($0.serverId, $0) }, uniquingKeysWith: { first, _ in first })
        for remote in remotes {
            if let local = byId[Model.remoteId(remote)] {
                local.update(from: remote)
            } else {
                context.insert(Model(from: remote))
            }
        }
    }

    @MainActor
    private func removeDeleted(in context: ModelContext) throws {
        let idsByTable = Dictionary(grouping: deletions, by: \.table).mapValues { $0.map(\.id) }
        try remove(LocalWallet.self, ids: idsByTable["wallets"], in: context)
        try remove(LocalCategory.self, ids: idsByTable["user_categories"], in: context)
        try remove(LocalTransaction.self, ids: idsByTable["transactions"], in: context)
        try remove(LocalBudget.self, ids: idsByTable["budgets"], in: context)
        try remove(LocalDebt.self, ids: idsByTable["debts"], in: context)
        try remove(LocalSavingGoal.self, ids: idsByTable["saving_goals"], in: context)
        try remove(LocalRecurringTransaction.self, ids: idsByTable["recurring_transactions"], in: context)
    }

    @MainActor
    private func remove<Model: ServerBacked>(_ type: Model.Type, ids: [UUID]?, in context: ModelContext) throws {
        guard let ids, !ids.isEmpty else { return }
        for local in try context.fetch(Model.withServerIds(ids)) {
            context.delete(local)
        }
    }

    /// Rows store their wallet's name from the join; renaming a wallet does not touch
    /// them on the server, so a delta would otherwise leave the old name showing.
    @MainActor
    private func refreshWalletNames(in context: ModelContext) throws {
        for wallet in wallets {
            let walletId: UUID? = wallet.id
            let transactions = FetchDescriptor<LocalTransaction>(predicate: #Predicate { $0.walletId == walletId })
            for tx in try context.fetch(transactions) {
                tx.setIfChanged(\.walletName, wallet.name)
            }
            let rules = FetchDescriptor<LocalRecurringTransaction>(predicate: #Predicate { $0.walletId == walletId })
            for rule in try context.fetch(rules) {
                rule.setIfChanged(\.walletName, wallet.name)
            }
        }
    }

    /// Same as `refreshWalletNames`, for the category name, icon and color copied onto rows.
    @MainActor
    private func refreshCategoryDetails(in context: ModelContext) throws {
        for category in categories {
            let categoryId: UUID? = category.id
            for tx in try context.fetch(FetchDescriptor<LocalTransaction>(
                predicate: #Predicate { $0.categoryId == categoryId })) {
                tx.setIfChanged(\.categoryName, category.displayName)
                tx.setIfChanged(\.categoryIcon, category.icon)
                tx.setIfChanged(\.categoryColor, category.color)
            }
            for budget in try context.fetch(FetchDescriptor<LocalBudget>(
                predicate: #Predicate { $0.categoryId == categoryId })) {
                budget.setIfChanged(\.categoryName, category.displayName)
                budget.setIfChanged(\.categoryIcon, category.icon)
                budget.setIfChanged(\.categoryColor, category.color)
            }
            for rule in try context.fetch(FetchDescriptor<LocalRecurringTransaction>(
                predicate: #Predicate { $0.categoryId == categoryId })) {
                rule.setIfChanged(\.categoryName, category.displayName)
                rule.setIfChanged(\.categoryIcon, category.icon)
                rule.setIfChanged(\.categoryColor, category.color)
            }
        }
    }
}

extension PostgrestClient {
    func readChangedRows<Row: Decodable & Identifiable>(
        _ table: String, columns: String = "*", userId: UUID, since: String
    ) async throws -> [Row] where Row.ID: PostgrestFilterValue {
        try await readRows {
            from(table).select(columns).eq("user_id", value: userId).gt("updated_at", value: since)
        }
    }
}
