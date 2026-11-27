import Foundation
import SwiftData
import Supabase

@MainActor
final class WalletService {
    static let shared = WalletService()
    private init() {}

    func create(
        name: String, type: WalletKind, initialBalance: Decimal,
        icon: String?, color: String?, isDefault: Bool,
        creditLimit: Decimal? = nil, statementDay: Int? = nil, paymentDueDay: Int? = nil,
        in ctx: ModelContext
    ) async throws {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let client = mutation.client
        let limit = type == .credit ? creditLimit : nil
        let params = NewWallet(
            p_name: name, p_type: type,
            p_balance: type == .credit ? limit ?? 0 : initialBalance,
            p_icon: icon, p_color: color, p_is_default: isDefault,
            p_credit_limit: limit, p_statement_day: statementDay, p_payment_due_day: paymentDueDay
        )
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
        struct Params: Encodable {
            let p_wallet_id: String
            let p_date: String
        }
        try await RPCResultApplier.perform("delete_wallet", in: ctx) { _ in
            Params(
                p_wallet_id: wallet.serverId.uuidString,
                p_date: LedgerDate.string(from: Date())
            )
        }
    }

    /// Records the gap between the tracked balance and a real-world one.
    ///
    /// Which direction the gap runs is only knowable once the wallet row is
    /// locked, so both candidate categories are passed down and the database
    /// picks — guessing here and sending one would be wrong whenever another
    /// write lands in between.
    func reconcile(
        _ wallet: LocalWallet, actualBalance: Decimal, note: String?,
        date: Date = Date(), in ctx: ModelContext
    ) async throws {
        struct Params: Encodable {
            let p_wallet_id: String
            let p_actual_balance: Decimal
            let p_date: String
            let p_category_up: String?
            let p_category_down: String?
            let p_note: String?
        }
        try await RPCResultApplier.perform("reconcile_wallet", in: ctx) { client in
            let up = try await CategoryService.shared.ensureSystemCategory(SystemCategory.adjustUp, using: client)
            let down = try await CategoryService.shared.ensureSystemCategory(SystemCategory.adjustDown, using: client)
            return Params(
                p_wallet_id: wallet.serverId.uuidString,
                p_actual_balance: actualBalance,
                p_date: LedgerDate.string(from: date),
                p_category_up: up.uuidString,
                p_category_down: down.uuidString,
                p_note: note?.isEmpty == true ? "Reconciled \(wallet.name)" : note
            )
        }
    }

    /// Paying a card raises its available credit and lowers the source wallet,
    /// written as a transfer pair.
    func payCredit(
        _ creditWallet: LocalWallet, from sourceWallet: LocalWallet,
        amount: Decimal, date: Date, note: String?,
        in ctx: ModelContext
    ) async throws {
        struct Params: Encodable {
            let p_card_wallet_id: String
            let p_from_wallet_id: String
            let p_amount: Decimal
            let p_date: String
            let p_note: String?
        }
        try await RPCResultApplier.perform("pay_credit_card", in: ctx) { _ in
            Params(
                p_card_wallet_id: creditWallet.serverId.uuidString,
                p_from_wallet_id: sourceWallet.serverId.uuidString,
                p_amount: amount,
                p_date: LedgerDate.string(from: date),
                p_note: note?.isEmpty == true ? nil : note
            )
        }
    }
}

/// `create_wallet` arguments. Every argument is sent, `null` included — the function
/// declares no defaults, so an omitted key would not match its signature.
private struct NewWallet: Encodable {
    let p_name: String
    let p_type: WalletKind
    let p_balance: Decimal
    let p_icon: String?
    let p_color: String?
    let p_is_default: Bool
    let p_credit_limit: Decimal?
    let p_statement_day: Int?
    let p_payment_due_day: Int?

    private enum CodingKeys: String, CodingKey {
        case p_name, p_type, p_balance, p_icon, p_color, p_is_default
        case p_credit_limit, p_statement_day, p_payment_due_day
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(p_name, forKey: .p_name)
        try container.encode(p_type, forKey: .p_type)
        try container.encode(p_balance, forKey: .p_balance)
        try container.encode(p_icon, forKey: .p_icon)
        try container.encode(p_color, forKey: .p_color)
        try container.encode(p_is_default, forKey: .p_is_default)
        try container.encode(p_credit_limit, forKey: .p_credit_limit)
        try container.encode(p_statement_day, forKey: .p_statement_day)
        try container.encode(p_payment_due_day, forKey: .p_payment_due_day)
    }
}
