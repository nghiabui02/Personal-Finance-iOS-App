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

    static func apply(_ envelope: RPC.Envelope, in ctx: ModelContext) throws {
        upsertTransactions(envelope.transactions, in: ctx)
        deleteTransactions(ids: envelope.deletedTransactionIds, in: ctx)
        deleteWallets(ids: envelope.deletedWalletIds, in: ctx)
        applyBalances(envelope.wallets, in: ctx)
        upsertDebt(envelope.debt, in: ctx)
        try ctx.save()
    }

    // MARK: - Pieces

    private static func upsertTransactions(_ remotes: [RemoteTransaction], in ctx: ModelContext) {
        guard !remotes.isEmpty else { return }
        let ids = remotes.map(\.id)
        let existing = fetch(LocalTransaction.self, in: ctx) { ids.contains($0.serverId) }
        let map = Dictionary(existing.map { ($0.serverId, $0) }, uniquingKeysWith: { first, _ in first })
        for remote in remotes {
            if let local = map[remote.id] { local.update(from: remote) }
            else { ctx.insert(LocalTransaction(from: remote)) }
        }
    }

    private static func deleteTransactions(ids: [UUID], in ctx: ModelContext) {
        guard !ids.isEmpty else { return }
        for local in fetch(LocalTransaction.self, in: ctx, where: { ids.contains($0.serverId) }) {
            ctx.delete(local)
        }
    }

    /// Removing a wallet also detaches everything that pointed at it.
    ///
    /// The server clears `wallet_id` by foreign key, which can touch thousands of
    /// rows, so the envelope reports only the id and leaves the client to do the
    /// same locally. Skipping this would leave rows referencing a wallet that no
    /// longer exists.
    private static func deleteWallets(ids: [UUID], in ctx: ModelContext) {
        guard !ids.isEmpty else { return }

        for tx in fetch(LocalTransaction.self, in: ctx, where: { ids.contains($0.walletId ?? UUID()) }) {
            tx.walletId = nil
            tx.walletName = "Deleted wallet"
        }
        for debt in fetch(LocalDebt.self, in: ctx, where: { ids.contains($0.walletId ?? UUID()) }) {
            debt.walletId = nil
        }
        for rec in fetch(LocalRecurringTransaction.self, in: ctx, where: { ids.contains($0.walletId ?? UUID()) }) {
            rec.walletId = nil
            rec.walletName = nil
        }
        for wallet in fetch(LocalWallet.self, in: ctx, where: { ids.contains($0.serverId) }) {
            ctx.delete(wallet)
        }
    }

    /// Inserts as well as updates — `create_debt` reports a debt the local store
    /// has never seen, and skipping it would hide the new debt until the next sync.
    private static func upsertDebt(_ remote: RemoteDebt?, in ctx: ModelContext) {
        guard let remote else { return }
        let id = remote.id
        if let local = fetch(LocalDebt.self, in: ctx, where: { $0.serverId == id }).first {
            local.update(from: remote)
        } else {
            ctx.insert(LocalDebt(from: remote))
        }
    }

    private static func applyBalances(_ balances: [RPC.WalletBalance], in ctx: ModelContext) {
        guard !balances.isEmpty else { return }
        let ids = balances.map(\.id)
        let wallets = fetch(LocalWallet.self, in: ctx) { ids.contains($0.serverId) }
        let map = Dictionary(wallets.map { ($0.serverId, $0) }, uniquingKeysWith: { first, _ in first })
        for balance in balances {
            map[balance.id]?.balance = balance.balance
        }
    }

    private static func fetch<T: PersistentModel>(
        _ type: T.Type,
        in ctx: ModelContext,
        where predicate: (T) -> Bool
    ) -> [T] {
        // Fetched unfiltered then filtered in memory: #Predicate cannot capture a
        // closure, and these sets are a handful of rows per call.
        let all = (try? ctx.fetch(FetchDescriptor<T>())) ?? []
        return all.filter(predicate)
    }
}
