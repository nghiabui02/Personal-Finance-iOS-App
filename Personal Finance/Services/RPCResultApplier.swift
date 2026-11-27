import Foundation
import Supabase
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
            let memberships = try upsertTransactions(envelope.transactions, in: ctx)
            try deleteTransactions(ids: envelope.deletedTransactionIds, in: ctx)
            try deleteWallets(ids: envelope.deletedWalletIds, in: ctx)
            try applyBalances(envelope.wallets, in: ctx)
            try upsertDebt(envelope.debt, in: ctx)
            try ctx.save()
            CategoryDirectory.shared.merge(memberships)
        } catch {
            ctx.rollback()
            SyncManager.shared.requestSync(modelContext: ctx)
            throw BusinessRuleError(message: "The server saved the change. The app will refresh its local copy.")
        }
    }

    /// Runs one money function as a single mutation: claims the mutation slot, builds the
    /// parameters (which may need the request's client, e.g. to resolve a system
    /// category), calls `function`, mirrors the envelope locally, and turns any failure
    /// into an error worth showing.
    @discardableResult
    static func perform<Params: Encodable & Sendable>(
        _ function: String, in ctx: ModelContext, params: (PostgrestClient) async throws -> Params
    ) async throws -> RPC.Envelope {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        do {
            let parameters = try await params(mutation.client)
            let result: RPC.Envelope = try await mutation.client.rpc(function, params: parameters).execute().value
            try apply(result, for: mutation.session, in: ctx)
            return result
        } catch {
            throw error.asDisplayableError()
        }
    }

    // MARK: - Pieces

    private static func upsertTransactions(_ remotes: [RemoteTransaction], in ctx: ModelContext) throws -> [RemoteCategory] {
        guard !remotes.isEmpty else { return [] }
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
        return remotes.compactMap { row in
            guard let category = row.categories, let key = category.systemKey, category.isActive,
                  knownIds.insert(category.id).inserted else { return nil }
            let membership = RemoteCategory(
                id: category.id, name: category.name, type: row.type, icon: category.icon, color: category.color,
                templateId: nil, systemKey: key, isActive: true, template: nil
            )
            ctx.insert(LocalCategory(from: membership))
            return membership
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

        // One fetch per wallet: optional equality is the form #Predicate reliably
        // turns into SQL, and an operation removes one wallet at a time anyway.
        for id in ids {
            let walletId: UUID? = id
            for tx in try ctx.fetch(FetchDescriptor<LocalTransaction>(predicate: #Predicate { $0.walletId == walletId })) {
                tx.walletId = nil
                tx.walletName = "Deleted wallet"
            }
            for debt in try ctx.fetch(FetchDescriptor<LocalDebt>(predicate: #Predicate { $0.walletId == walletId })) {
                debt.walletId = nil
            }
            let recurring = FetchDescriptor<LocalRecurringTransaction>(predicate: #Predicate { $0.walletId == walletId })
            for rec in try ctx.fetch(recurring) {
                rec.walletId = nil
                rec.walletName = nil
            }
        }
        for wallet in try ctx.fetch(FetchDescriptor<LocalWallet>(predicate: #Predicate { ids.contains($0.serverId) })) {
            ctx.delete(wallet)
        }
    }

    /// Inserts as well as updates — `create_debt` reports a debt the local store
    /// has never seen, and skipping it would hide the new debt until the next sync.
    private static func upsertDebt(_ remote: RemoteDebt?, in ctx: ModelContext) throws {
        guard let remote else { return }
        let id = remote.id
        var descriptor = FetchDescriptor<LocalDebt>(predicate: #Predicate { $0.serverId == id })
        descriptor.fetchLimit = 1
        if let local = try ctx.fetch(descriptor).first {
            local.update(from: remote)
        } else {
            ctx.insert(LocalDebt(from: remote))
        }
    }

    private static func applyBalances(_ balances: [RPC.WalletBalance], in ctx: ModelContext) throws {
        guard !balances.isEmpty else { return }
        let ids = balances.map(\.id)
        let wallets = try ctx.fetch(FetchDescriptor<LocalWallet>(predicate: #Predicate { ids.contains($0.serverId) }))
        let map = Dictionary(wallets.map { ($0.serverId, $0) }, uniquingKeysWith: { first, _ in first })
        for balance in balances {
            map[balance.id]?.balance = balance.balance
        }
    }
}
