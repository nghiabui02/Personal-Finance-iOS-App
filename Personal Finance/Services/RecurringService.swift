import Foundation
import SwiftData
import Supabase

/// What the recurring-rule form submits. `update` leaves `type` and `startDate` alone:
/// both are fixed once the rule exists.
struct RecurringRuleDraft {
    var type: TransactionKind
    var amount: Decimal
    var frequency: RecurringFrequency
    var startDate: Date
    var endDate: Date?
    var walletId: UUID?
    var categoryId: UUID?
    var note: String?
    var bankFee: Decimal
}

@MainActor
final class RecurringService {
    static let shared = RecurringService()
    private init() {}

    func create(_ draft: RecurringRuleDraft, in ctx: ModelContext) async throws {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let client = mutation.client
        struct Body: Encodable {
            let user_id: String, type: TransactionKind, amount: Decimal, frequency: RecurringFrequency
            let start_date: String, end_date: String?, next_run_date: String
            let wallet_id: String?, user_category_id: String?, note: String?
            let bank_fee: Decimal?, active: Bool
        }
        let remote: RemoteRecurringTransaction = try await client
            .from("recurring_transactions")
            .insert(Body(
                user_id: mutation.userId.uuidString, type: draft.type, amount: draft.amount,
                frequency: draft.frequency,
                start_date: LedgerDate.dayFormatter.string(from: draft.startDate),
                end_date: draft.endDate.map { LedgerDate.dayFormatter.string(from: $0) },
                next_run_date: LedgerDate.dayFormatter.string(from: draft.startDate),
                wallet_id: draft.walletId?.uuidString, user_category_id: draft.categoryId?.uuidString,
                note: draft.note?.isEmpty == true ? nil : draft.note,
                bank_fee: draft.bankFee > 0 ? draft.bankFee : nil, active: true
            ))
            .select(CategoryProjection.withWallet)
            .single().execute().value
        try LocalDataStore.validate(mutation.session)
        ctx.insert(LocalRecurringTransaction(from: remote))
        try LocalDataStore.saveMutation(in: ctx)
    }

    func update(_ rec: LocalRecurringTransaction, with draft: RecurringRuleDraft, in ctx: ModelContext) async throws {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let client = mutation.client
        let body = RuleUpdate(
            amount: draft.amount, frequency: draft.frequency,
            end_date: draft.endDate.map { LedgerDate.string(from: $0) },
            wallet_id: draft.walletId, user_category_id: draft.categoryId,
            note: draft.note?.isEmpty == true ? nil : draft.note,
            bank_fee: draft.bankFee > 0 ? draft.bankFee : nil
        )
        let remote: RemoteRecurringTransaction = try await client
            .from("recurring_transactions")
            .update(body)
            .eq("id", value: rec.serverId)
            .eq("user_id", value: mutation.userId.uuidString)
            .select(CategoryProjection.withWallet)
            .single().execute().value
        try LocalDataStore.validate(mutation.session)
        rec.update(from: remote)
        try LocalDataStore.saveMutation(in: ctx)
    }

    func toggleActive(_ rec: LocalRecurringTransaction, in ctx: ModelContext) async throws {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let client = mutation.client
        let remote: RemoteRecurringTransaction = try await client.from("recurring_transactions")
            .update(["active": !rec.active])
            .eq("id", value: rec.serverId)
            .eq("user_id", value: mutation.userId)
            .select(CategoryProjection.withWallet).single().execute().value
        try LocalDataStore.validate(mutation.session)
        rec.update(from: remote)
        try LocalDataStore.saveMutation(in: ctx)
    }

    func skip(_ rec: LocalRecurringTransaction, in ctx: ModelContext) async throws {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let client = mutation.client
        let remote: RemoteRecurringTransaction? = try await client
            .rpc("skip_recurring_occurrence", params: ["p_id": rec.serverId])
            .execute().value
        guard let remote else {
            throw BusinessRuleError(message: "This recurring rule no longer exists. Refresh and try again.")
        }
        try LocalDataStore.validate(mutation.session)
        rec.nextRunDate = remote.nextRunDate?.date
        rec.updatedAt = remote.updatedAt
        rec.active = remote.active
        try LocalDataStore.saveMutation(in: ctx)
    }

    func delete(_ rec: LocalRecurringTransaction, in ctx: ModelContext) async throws {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let client = mutation.client
        try await client.from("recurring_transactions").delete()
            .eq("id", value: rec.serverId)
            .eq("user_id", value: mutation.userId.uuidString)
            .execute()
        try LocalDataStore.validate(mutation.session)
        ctx.delete(rec)
        try LocalDataStore.saveMutation(in: ctx)
    }
}

/// Every editable column of a rule. A cleared field must reach the server as an
/// explicit `null`; synthesized encoding would drop the key and keep the old value.
private struct RuleUpdate: Encodable {
    let amount: Decimal
    let frequency: RecurringFrequency
    let end_date: String?
    let wallet_id: UUID?
    let user_category_id: UUID?
    let note: String?
    let bank_fee: Decimal?

    private enum CodingKeys: String, CodingKey {
        case amount, frequency, end_date, wallet_id, user_category_id, note, bank_fee
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(amount, forKey: .amount)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(end_date, forKey: .end_date)
        try container.encode(wallet_id, forKey: .wallet_id)
        try container.encode(user_category_id, forKey: .user_category_id)
        try container.encode(note, forKey: .note)
        try container.encode(bank_fee, forKey: .bank_fee)
    }
}
