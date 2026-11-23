import Foundation
import SwiftData
import Supabase

@MainActor
final class WalletService {
    static let shared = WalletService()
    private init() {}

    func create(
        name: String, type: String, initialBalance: Double,
        icon: String?, color: String?, isDefault: Bool,
        creditLimit: Double? = nil, statementDay: Int? = nil, paymentDueDay: Int? = nil,
        in ctx: ModelContext
    ) async throws {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let client = mutation.client
        let limit = type == "credit" ? creditLimit : nil
        let params: [String: AnyJSON] = [
            "p_name": .string(name), "p_type": .string(type),
            "p_balance": .double(type == "credit" ? limit ?? 0 : initialBalance),
            "p_icon": icon.map(AnyJSON.string) ?? .null,
            "p_color": color.map(AnyJSON.string) ?? .null,
            "p_is_default": .bool(isDefault),
            "p_credit_limit": limit.map(AnyJSON.double) ?? .null,
            "p_statement_day": statementDay.map(AnyJSON.integer) ?? .null,
            "p_payment_due_day": paymentDueDay.map(AnyJSON.integer) ?? .null
        ]
        let remote: RemoteWallet = try await client.rpc("create_wallet", params: params).execute().value
        let local = LocalWallet(from: remote)
        if isDefault {
            do {
                let defaults: [RemoteWallet] = try await client.from("wallets").select()
                    .eq("user_id", value: mutation.userId).eq("is_default", value: true)
                    .limit(1).execute().value
                try LocalDataStore.validate(mutation.session)
                let defaultId = defaults.first?.id
                for wallet in try ctx.fetch(FetchDescriptor<LocalWallet>()) {
                    wallet.isDefault = wallet.serverId == defaultId
                }
                local.isDefault = local.serverId == defaultId
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                SyncManager.shared.requestSync(modelContext: ctx)
                throw BusinessRuleError(message: "The wallet was created. The app will refresh your wallets.")
            }
        }
        try LocalDataStore.validate(mutation.session)
        ctx.insert(local)
        try LocalDataStore.saveMutation(in: ctx)
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
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let client = mutation.client
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw FinanceValidationError.invalidWalletName }

        struct Body: Encodable { let name: String, color: String? }
        let remote: RemoteWallet = try await client
            .from("wallets")
            .update(Body(name: trimmedName, color: color))
            .eq("id", value: wallet.serverId)
            .eq("user_id", value: mutation.userId.uuidString)
            .select().single().execute().value
        try LocalDataStore.validate(mutation.session)
        wallet.update(from: remote)
        try LocalDataStore.saveMutation(in: ctx)
    }

    /// Moving a leftover balance to the default wallet and removing the wallet
    /// happen together. Past transactions keep their history — the foreign key
    /// clears `wallet_id` rather than deleting them.
    func delete(_ wallet: LocalWallet, in ctx: ModelContext) async throws {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let client = mutation.client
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
            try RPCResultApplier.apply(result, for: mutation.session, in: ctx)
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
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let client = mutation.client
        let up = try await CategoryService.shared.ensureSystemCategory(SystemCategory.adjustUp, using: client)
        let down = try await CategoryService.shared.ensureSystemCategory(SystemCategory.adjustDown, using: client)

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
                    p_category_up: up.uuidString,
                    p_category_down: down.uuidString,
                    p_note: note?.isEmpty == true ? "Reconciled \(wallet.name)" : note
                ))
                .execute().value
            try RPCResultApplier.apply(result, for: mutation.session, in: ctx)
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
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let client = mutation.client
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
            try RPCResultApplier.apply(result, for: mutation.session, in: ctx)
        } catch {
            throw error.asDisplayableError()
        }
    }
}
