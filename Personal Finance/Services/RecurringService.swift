import Foundation
import SwiftData
import Supabase

@MainActor
final class RecurringService {
    static let shared = RecurringService()
    private init() {}

    func create(
        type: String, amount: Double, frequency: String,
        startDate: Date, endDate: Date?,
        walletId: UUID?, categoryId: UUID?, note: String?,
        bankFee: Double = 0,
        in ctx: ModelContext
    ) async throws {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let client = mutation.client
        struct Body: Encodable {
            let user_id: String, type: String, amount: Double, frequency: String
            let start_date: String, end_date: String?, next_run_date: String
            let wallet_id: String?, user_category_id: String?, note: String?
            let bank_fee: Double?, active: Bool
        }
        let remote: RemoteRecurringTransaction = try await client
            .from("recurring_transactions")
            .insert(Body(
                user_id: mutation.userId.uuidString, type: type, amount: amount, frequency: frequency,
                start_date: LedgerDate.dayFormatter.string(from: startDate),
                end_date: endDate.map { LedgerDate.dayFormatter.string(from: $0) },
                next_run_date: LedgerDate.dayFormatter.string(from: startDate),
                wallet_id: walletId?.uuidString, user_category_id: categoryId?.uuidString,
                note: note?.isEmpty == true ? nil : note,
                bank_fee: bankFee > 0 ? bankFee : nil, active: true
            ))
            .select(CategoryProjection.withWallet)
            .single().execute().value
        try LocalDataStore.validate(mutation.session)
        ctx.insert(LocalRecurringTransaction(from: remote))
        try LocalDataStore.saveMutation(in: ctx)
    }

    func update(
        _ rec: LocalRecurringTransaction, amount: Double, frequency: String,
        endDate: Date?, walletId: UUID?, categoryId: UUID?, note: String?,
        bankFee: Double,
        in ctx: ModelContext
    ) async throws {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let client = mutation.client
        let body: [String: AnyJSON] = [
            "amount": .double(amount), "frequency": .string(frequency),
            "end_date": endDate.map { .string(LedgerDate.string(from: $0)) } ?? .null,
            "wallet_id": walletId.map { .string($0.uuidString) } ?? .null,
            "user_category_id": categoryId.map { .string($0.uuidString) } ?? .null,
            "note": note.flatMap { $0.isEmpty ? nil : .string($0) } ?? .null,
            "bank_fee": bankFee > 0 ? .double(bankFee) : .null
        ]
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
        rec.nextRunDate = remote.nextRunDate.flatMap(LedgerDate.date(from:))
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
