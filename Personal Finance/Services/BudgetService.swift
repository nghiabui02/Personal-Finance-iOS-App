import Foundation
import SwiftData

@MainActor
final class BudgetService {
    static let shared = BudgetService()
    private init() {}

    func create(categoryId: UUID?, amount: Double, month: Date, rollover: Bool = false, in ctx: ModelContext) async throws {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let client = mutation.client
        let monthStr = monthString(from: month)
        struct Body: Encodable {
            let user_id: String, user_category_id: String?, amount: Double, month: String, rollover: Bool
        }
        let remote: RemoteBudget = try await client
            .from("budgets")
            .insert(Body(user_id: mutation.userId.uuidString, user_category_id: categoryId?.uuidString,
                         amount: amount, month: monthStr, rollover: rollover))
            .select(CategoryProjection.withCategory).single().execute().value
        try LocalDataStore.validate(mutation.session)
        ctx.insert(LocalBudget(from: remote))
        try LocalDataStore.saveMutation(in: ctx)
    }

    func update(_ budget: LocalBudget, amount: Double, rollover: Bool, active: Bool, in ctx: ModelContext) async throws {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let client = mutation.client
        struct Body: Encodable { let amount: Double; let rollover: Bool; let active: Bool }
        let remote: RemoteBudget = try await client
            .from("budgets")
            .update(Body(amount: amount, rollover: rollover, active: active))
            .eq("id", value: budget.serverId)
            .eq("user_id", value: mutation.userId.uuidString)
            .select(CategoryProjection.withCategory).single().execute().value
        try LocalDataStore.validate(mutation.session)
        budget.update(from: remote)
        try LocalDataStore.saveMutation(in: ctx)
    }

    func toggleActive(_ budget: LocalBudget, active: Bool, in ctx: ModelContext) async throws {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let client = mutation.client
        struct Body: Encodable { let active: Bool }
        let remote: RemoteBudget = try await client
            .from("budgets")
            .update(Body(active: active))
            .eq("id", value: budget.serverId)
            .eq("user_id", value: mutation.userId.uuidString)
            .select(CategoryProjection.withCategory).single().execute().value
        try LocalDataStore.validate(mutation.session)
        budget.update(from: remote)
        try LocalDataStore.saveMutation(in: ctx)
    }

    func delete(_ budget: LocalBudget, in ctx: ModelContext) async throws {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let client = mutation.client
        try await client.from("budgets").delete()
            .eq("id", value: budget.serverId)
            .eq("user_id", value: mutation.userId.uuidString)
            .execute()
        try LocalDataStore.validate(mutation.session)
        ctx.delete(budget)
        try LocalDataStore.saveMutation(in: ctx)
    }

    private func monthString(from date: Date) -> String {
        LedgerDate.string(from: LedgerDate.startOfMonth(for: date) ?? date)
    }
}
