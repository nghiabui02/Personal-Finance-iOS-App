import Foundation
import SwiftData

@MainActor
final class TransactionService {
    static let shared = TransactionService()
    private let client = SupabaseService.shared.client
    private init() {}

    private let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        return f
    }()

    func create(
        type: String, amount: Double, date: Date,
        walletId: UUID?, categoryId: UUID?, note: String?,
        wallet: LocalWallet?,
        in ctx: ModelContext
    ) async throws {
        let userId = try await client.auth.session.user.id
        struct Body: Encodable {
            let user_id: String, type: String, amount: Double
            let transaction_date: String
            let wallet_id: String?, category_id: String?, note: String?
        }
        let remote: RemoteTransaction = try await client
            .from("transactions")
            .insert(Body(
                user_id: userId.uuidString, type: type, amount: amount,
                transaction_date: df.string(from: date),
                wallet_id: walletId?.uuidString,
                category_id: categoryId?.uuidString,
                note: note?.isEmpty == true ? nil : note
            ))
            .select("*, categories(id, name, icon, color), wallets(id, name)")
            .single().execute().value

        ctx.insert(LocalTransaction(from: remote))

        if let wallet {
            let delta = type == "income" ? amount : -amount
            try await applyBalanceDelta(delta, to: wallet)
        }
        try ctx.save()
    }

    func update(
        _ tx: LocalTransaction,
        type: String, amount: Double, date: Date,
        walletId: UUID?, categoryId: UUID?, note: String?,
        oldWallet: LocalWallet?, newWallet: LocalWallet?,
        in ctx: ModelContext
    ) async throws {
        struct Body: Encodable {
            let type: String, amount: Double, transaction_date: String
            let wallet_id: String?, category_id: String?, note: String?
        }
        let remote: RemoteTransaction = try await client
            .from("transactions")
            .update(Body(
                type: type, amount: amount,
                transaction_date: df.string(from: date),
                wallet_id: walletId?.uuidString,
                category_id: categoryId?.uuidString,
                note: note?.isEmpty == true ? nil : note
            ))
            .eq("id", value: tx.serverId)
            .select("*, categories(id, name, icon, color), wallets(id, name)")
            .single().execute().value

        // Reverse old wallet effect, apply new effect
        let oldEffect = tx.type == "income" ? tx.amount : -tx.amount
        let newEffect = type == "income" ? amount : -amount

        if let ow = oldWallet, let nw = newWallet, ow.serverId == nw.serverId {
            let net = newEffect - oldEffect
            if net != 0 { try await applyBalanceDelta(net, to: ow) }
        } else {
            if let ow = oldWallet { try await applyBalanceDelta(-oldEffect, to: ow) }
            if let nw = newWallet { try await applyBalanceDelta(newEffect, to: nw) }
        }

        tx.update(from: remote)
        try ctx.save()
    }

    func delete(_ tx: LocalTransaction, wallet: LocalWallet?, in ctx: ModelContext) async throws {
        try await client.from("transactions").delete().eq("id", value: tx.serverId).execute()

        if let wallet {
            let reverse = tx.type == "income" ? -tx.amount : tx.amount
            try await applyBalanceDelta(reverse, to: wallet)
        }
        ctx.delete(tx)
        try ctx.save()
    }

    private func applyBalanceDelta(_ delta: Double, to wallet: LocalWallet) async throws {
        let newBalance = wallet.balance + delta
        struct B: Encodable { let balance: Double }
        try await client
            .from("wallets")
            .update(B(balance: newBalance))
            .eq("id", value: wallet.serverId)
            .execute()
        wallet.balance = newBalance
    }
}
