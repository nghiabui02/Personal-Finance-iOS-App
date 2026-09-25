import Foundation
import SwiftData

@MainActor
final class TransactionService {
    static let shared = TransactionService()
    private let client = SupabaseService.shared.client
    private init() {}

    func create(
        type: String, amount: Double, date: Date,
        walletId: UUID?, categoryId: UUID?, note: String?,
        wallet: LocalWallet?, bankFee: Double = 0,
        in ctx: ModelContext
    ) async throws {
        // amount is the base (pre-fee) value; the stored amount includes the fee,
        // matching web — bank_fee is kept only for display, never summed separately.
        let total = amount + bankFee
        if type == "expense", let wallet, !wallet.hasSufficientFunds(for: total) {
            throw FinanceValidationError.insufficientFunds
        }
        let userId = try await client.auth.session.user.id
        struct Body: Encodable {
            let user_id: String, type: String, amount: Double
            let transaction_date: String
            let wallet_id: String?, category_id: String?, note: String?
            let bank_fee: Double?
        }
        let remote: RemoteTransaction = try await client
            .from("transactions")
            .insert(Body(
                user_id: userId.uuidString, type: type, amount: total,
                transaction_date: LedgerDate.dayFormatter.string(from: date),
                wallet_id: walletId?.uuidString,
                category_id: categoryId?.uuidString,
                note: note?.isEmpty == true ? nil : note,
                bank_fee: bankFee > 0 ? bankFee : nil
            ))
            .select("*, categories(id, name, icon, color), wallets(id, name)")
            .single().execute().value

        ctx.insert(LocalTransaction(from: remote))

        if let wallet {
            let delta = type == "income" ? total : -total
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
        // Reverse old wallet effect, apply new effect
        let oldEffect = tx.type == "income" ? tx.amount : -tx.amount
        let newEffect = type == "income" ? amount : -amount

        if let ow = oldWallet, let nw = newWallet, ow.serverId == nw.serverId {
            let net = newEffect - oldEffect
            if net < 0, !ow.hasSufficientFunds(for: -net) {
                throw FinanceValidationError.insufficientFunds
            }
        } else if let nw = newWallet, newEffect < 0, !nw.hasSufficientFunds(for: -newEffect) {
            throw FinanceValidationError.insufficientFunds
        }

        let userId = try await client.auth.session.user.id
        struct Body: Encodable {
            let type: String, amount: Double, transaction_date: String
            let wallet_id: String?, category_id: String?, note: String?
        }
        let remote: RemoteTransaction = try await client
            .from("transactions")
            .update(Body(
                type: type, amount: amount,
                transaction_date: LedgerDate.dayFormatter.string(from: date),
                wallet_id: walletId?.uuidString,
                category_id: categoryId?.uuidString,
                note: note?.isEmpty == true ? nil : note
            ))
            .eq("id", value: tx.serverId)
            .eq("user_id", value: userId.uuidString)
            .select("*, categories(id, name, icon, color), wallets(id, name)")
            .single().execute().value

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
        let userId = try await client.auth.session.user.id
        try await client.from("transactions").delete()
            .eq("id", value: tx.serverId)
            .eq("user_id", value: userId.uuidString)
            .execute()

        if let wallet {
            let reverse = tx.type == "income" ? -tx.amount : tx.amount
            try await applyBalanceDelta(reverse, to: wallet)
        }
        ctx.delete(tx)
        try ctx.save()
    }

    private func applyBalanceDelta(_ delta: Double, to wallet: LocalWallet) async throws {
        let userId = try await client.auth.session.user.id
        struct Params: Encodable { let p_wallet_id: String, p_delta: Double, p_user_id: String }
        let newBalance: Double? = try await client
            .rpc("adjust_wallet_balance", params: Params(
                p_wallet_id: wallet.serverId.uuidString.lowercased(),
                p_delta: delta,
                p_user_id: userId.uuidString.lowercased()
            ))
            .execute().value
        guard let newBalance else { throw FinanceValidationError.walletNotFound }
        wallet.balance = newBalance
    }
}
