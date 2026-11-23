import Foundation
import SwiftData

/// Mirrors what a money RPC reports onto the local store.
///
/// The server already committed the change atomically; this only brings the
/// local copy in step so the UI matches without a re-sync. One entry point for
/// every operation means no function can quietly skip a wallet balance or leave
/// a debt stale — the kind of drift that shows up much later as a wrong number.
@MainActor
enum RPCResultApplier {

    static func apply(_ envelope: RPC.Envelope, for session: LocalDataStore.Session, in ctx: ModelContext) throws {
        try LocalDataStore.validate(session)
        do {
            try upsertTransactions(envelope.transactions, in: ctx)
            try deleteTransactions(ids: envelope.deletedTransactionIds, in: ctx)
            try deleteWallets(ids: envelope.deletedWalletIds, in: ctx)
            try applyBalances(envelope.wallets, in: ctx)
            try upsertDebt(envelope.debt, in: ctx)
            try ctx.save()
        } catch {
            ctx.rollback()
            SyncManager.shared.requestSync(modelContext: ctx)
            throw BusinessRuleError(message: "The server saved the change. The app will refresh its local copy.")
        }
    }

    // MARK: - Pieces

    private static func upsertTransactions(_ remotes: [RemoteTransaction], in ctx: ModelContext) throws {
        guard !remotes.isEmpty else { return }
        let ids = remotes.map(\.id)
        let existing = try ctx.fetch(FetchDescriptor<LocalTransaction>(
            predicate: #Predicate { ids.contains($0.serverId) }
        ))
        let map = Dictionary(existing.map { ($0.serverId, $0) }, uniquingKeysWith: { first, _ in first })
        let categoryIds = remotes.compactMap(\.categoryId)
        let categories = try ctx.fetch(FetchDescriptor<LocalCategory>(
            predicate: #Predicate { categoryIds.contains($0.serverId) }
        ))
        let names = Dictionary(categories.map { ($0.serverId, $0.name) }, uniquingKeysWith: { first, _ in first })
        for remote in remotes {
            let local: LocalTransaction
            if let existing = map[remote.id] {
                existing.update(from: remote)
                local = existing
            } else {
                local = LocalTransaction(from: remote)
                ctx.insert(local)
            }
            if remote.categories?.name == nil, remote.categories?.template?.defaultKey != nil,
               let id = remote.categoryId, let name = names[id] {
                local.categoryName = name
            }
        }
        var knownIds = Set(categories.map(\.serverId))
        for row in remotes {
            guard let category = row.categories, let key = category.systemKey, category.isActive,
                  knownIds.insert(category.id).inserted else { continue }
            ctx.insert(LocalCategory(from: RemoteCategory(
                id: category.id, name: category.name, type: row.type,
                icon: category.icon, color: category.color, templateId: nil, systemKey: key,
                isActive: true, template: nil
            )))
        }
    }

    private static func deleteTransactions(ids: [UUID], in ctx: ModelContext) throws {
        guard !ids.isEmpty else { return }
        let descriptor = FetchDescriptor<LocalTransaction>(predicate: #Predicate { ids.contains($0.serverId) })
        for local in try ctx.fetch(descriptor) {
            ctx.delete(local)
        }
    }

    /// Removing a wallet also detaches everything that pointed at it.
    ///
    /// The server clears `wallet_id` by foreign key, which can touch thousands of
    /// rows, so the envelope reports only the id and leaves the client to do the
    /// same locally. Skipping this would leave rows referencing a wallet that no
    /// longer exists.
    private static func deleteWallets(ids: [UUID], in ctx: ModelContext) throws {
        guard !ids.isEmpty else { return }

        for tx in try fetch(LocalTransaction.self, in: ctx, where: { $0.walletId.map(ids.contains) ?? false }) {
            tx.walletId = nil
            tx.walletName = "Deleted wallet"
        }
        for debt in try fetch(LocalDebt.self, in: ctx, where: { $0.walletId.map(ids.contains) ?? false }) {
            debt.walletId = nil
        }
        for rec in try fetch(LocalRecurringTransaction.self, in: ctx, where: { $0.walletId.map(ids.contains) ?? false }) {
            rec.walletId = nil
            rec.walletName = nil
        }
        for wallet in try fetch(LocalWallet.self, in: ctx, where: { ids.contains($0.serverId) }) {
            ctx.delete(wallet)
        }
    }

    /// Inserts as well as updates — `create_debt` reports a debt the local store
    /// has never seen, and skipping it would hide the new debt until the next sync.
    private static func upsertDebt(_ remote: RemoteDebt?, in ctx: ModelContext) throws {
        guard let remote else { return }
        let id = remote.id
        if let local = try fetch(LocalDebt.self, in: ctx, where: { $0.serverId == id }).first {
            local.update(from: remote)
        } else {
            ctx.insert(LocalDebt(from: remote))
        }
    }

    private static func applyBalances(_ balances: [RPC.WalletBalance], in ctx: ModelContext) throws {
        guard !balances.isEmpty else { return }
        let ids = balances.map(\.id)
        let wallets = try fetch(LocalWallet.self, in: ctx) { ids.contains($0.serverId) }
        let map = Dictionary(wallets.map { ($0.serverId, $0) }, uniquingKeysWith: { first, _ in first })
        for balance in balances {
            map[balance.id]?.balance = balance.balance
        }
    }

    private static func fetch<T: PersistentModel>(
        _ type: T.Type,
        in ctx: ModelContext,
        where predicate: (T) -> Bool
    ) throws -> [T] {
        // Fetched unfiltered then filtered in memory: #Predicate cannot capture a
        // closure, and these sets are a handful of rows per call.
        let all = try ctx.fetch(FetchDescriptor<T>())
        return all.filter(predicate)
    }
}
