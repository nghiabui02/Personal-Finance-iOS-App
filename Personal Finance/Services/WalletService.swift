import Foundation
import SwiftData

@MainActor
final class WalletService {
    static let shared = WalletService()
    private let client = SupabaseService.shared.client
    private init() {}

    func create(
        name: String, type: String, initialBalance: Double,
        icon: String?, color: String?, isDefault: Bool,
        creditLimit: Double? = nil, statementDay: Int? = nil, paymentDueDay: Int? = nil,
        in ctx: ModelContext
    ) async throws {
        let userId = try await client.auth.session.user.id
        let remote: RemoteWallet
        if type == "credit" {
            struct CreditBody: Encodable {
                let user_id: String, name: String, type: String, balance: Double
                let icon: String?, color: String?, is_default: Bool
                let credit_limit: Double, statement_day: Int?, payment_due_day: Int?
            }
            let limit = creditLimit ?? 0
            remote = try await client
                .from("wallets")
                .insert(CreditBody(user_id: userId.uuidString, name: name, type: type,
                                   balance: limit, icon: icon, color: color, is_default: isDefault,
                                   credit_limit: limit, statement_day: statementDay,
                                   payment_due_day: paymentDueDay))
                .select().single().execute().value
        } else {
            struct Body: Encodable {
                let user_id: String, name: String, type: String, balance: Double
                let icon: String?, color: String?, is_default: Bool
            }
            remote = try await client
                .from("wallets")
                .insert(Body(user_id: userId.uuidString, name: name, type: type,
                             balance: initialBalance, icon: icon, color: color, is_default: isDefault))
                .select().single().execute().value
        }
        ctx.insert(LocalWallet(from: remote))
        try ctx.save()
    }

    /// Only `name` and `color` are editable.
    ///
    /// Everything else is structural: `balance` must only ever move through a
    /// transaction or Reconcile, or the transaction history stops adding up to it —
    /// and changing `credit_limit` on an existing card used to silently rewrite
    /// `balance` along with it. Type/limit/statement days are fixed at creation.
    func update(
        _ wallet: LocalWallet, name: String, color: String?,
        in ctx: ModelContext
    ) async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw FinanceValidationError.invalidWalletName }

        let userId = try await client.auth.session.user.id
        struct Body: Encodable { let name: String, color: String? }
        let remote: RemoteWallet = try await client
            .from("wallets")
            .update(Body(name: trimmedName, color: color))
            .eq("id", value: wallet.serverId)
            .eq("user_id", value: userId.uuidString)
            .select().single().execute().value
        wallet.update(from: remote)
        try ctx.save()
    }

    /// Moving a leftover balance to the default wallet and removing the wallet
    /// happen together. Past transactions keep their history — the foreign key
    /// clears `wallet_id` rather than deleting them.
    func delete(_ wallet: LocalWallet, in ctx: ModelContext) async throws {
        struct Params: Encodable {
            let p_wallet_id: String
            let p_date: String
        }
        do {
            let result: RPC.Envelope = try await client
                .rpc("delete_wallet", params: Params(
                    p_wallet_id: wallet.serverId.uuidString,
                    p_date: LedgerDate.string(from: Date())
                ))
                .execute().value
            try RPCResultApplier.apply(result, in: ctx)
        } catch {
            throw error.asDisplayableError()
        }
    }

    /// Records the gap between the tracked balance and a real-world one.
    ///
    /// Which direction the gap runs is only knowable once the wallet row is
    /// locked, so both candidate categories are passed down and the database
    /// picks — guessing here and sending one would be wrong whenever another
    /// write lands in between.
    func reconcile(
        _ wallet: LocalWallet, actualBalance: Double, note: String?,
        date: Date = Date(), in ctx: ModelContext
    ) async throws {
        // Created on demand: an account that has never reconciled has neither
        // category yet, and the first attempt would otherwise fail.
        let up = try await CategoryService.shared.ensureSystemCategory(
            SystemCategory.adjustUp, type: "income",
            name: SystemCategory.Adjustment.name,
            icon: SystemCategory.Adjustment.icon,
            color: SystemCategory.Adjustment.color,
            in: ctx
        )
        let down = try await CategoryService.shared.ensureSystemCategory(
            SystemCategory.adjustDown, type: "expense",
            name: SystemCategory.Adjustment.name,
            icon: SystemCategory.Adjustment.icon,
            color: SystemCategory.Adjustment.color,
            in: ctx
        )

        struct Params: Encodable {
            let p_wallet_id: String
            let p_actual_balance: Double
            let p_date: String
            let p_category_up: String?
            let p_category_down: String?
            let p_note: String?
        }
        do {
            let result: RPC.Envelope = try await client
                .rpc("reconcile_wallet", params: Params(
                    p_wallet_id: wallet.serverId.uuidString,
                    p_actual_balance: actualBalance,
                    p_date: LedgerDate.string(from: date),
                    p_category_up: up.serverId.uuidString,
                    p_category_down: down.serverId.uuidString,
                    p_note: note?.isEmpty == true ? "Reconciled \(wallet.name)" : note
                ))
                .execute().value
            try RPCResultApplier.apply(result, in: ctx)
        } catch {
            throw error.asDisplayableError()
        }
    }

    /// Paying a card raises its available credit and lowers the source wallet,
    /// written as a transfer pair.
    func payCredit(
        _ creditWallet: LocalWallet, from sourceWallet: LocalWallet,
        amount: Double, date: Date, note: String?,
        in ctx: ModelContext
    ) async throws {
        struct Params: Encodable {
            let p_card_wallet_id: String
            let p_from_wallet_id: String
            let p_amount: Double
            let p_date: String
            let p_note: String?
        }
        do {
            let result: RPC.Envelope = try await client
                .rpc("pay_credit_card", params: Params(
                    p_card_wallet_id: creditWallet.serverId.uuidString,
                    p_from_wallet_id: sourceWallet.serverId.uuidString,
                    p_amount: amount,
                    p_date: LedgerDate.string(from: date),
                    p_note: note?.isEmpty == true ? nil : note
                ))
                .execute().value
            try RPCResultApplier.apply(result, in: ctx)
        } catch {
            throw error.asDisplayableError()
        }
    }
}
