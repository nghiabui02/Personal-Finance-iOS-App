import Foundation
import SwiftData

@MainActor
final class BudgetService {
    static let shared = BudgetService()
    private let client = SupabaseService.shared.client
    private init() {}

    func create(categoryId: UUID?, amount: Double, month: Date, rollover: Bool = false, in ctx: ModelContext) async throws {
        let userId = try await client.auth.session.user.id
        let monthStr = monthString(from: month)
        struct Body: Encodable {
            let user_id: String, category_id: String?, amount: Double, month: String, rollover: Bool
        }
        let remote: RemoteBudget = try await client
            .from("budgets")
            .insert(Body(user_id: userId.uuidString, category_id: categoryId?.uuidString,
                         amount: amount, month: monthStr, rollover: rollover))
            .select("*, categories(id, name, icon, color)").single().execute().value
        ctx.insert(LocalBudget(from: remote))
        try ctx.save()
    }

    func update(_ budget: LocalBudget, amount: Double, rollover: Bool, active: Bool, in ctx: ModelContext) async throws {
        let userId = try await client.auth.session.user.id
        struct Body: Encodable { let amount: Double; let rollover: Bool; let active: Bool }
        let remote: RemoteBudget = try await client
            .from("budgets")
            .update(Body(amount: amount, rollover: rollover, active: active))
            .eq("id", value: budget.serverId)
            .eq("user_id", value: userId.uuidString)
            .select("*, categories(id, name, icon, color)").single().execute().value
        budget.update(from: remote)
        try ctx.save()
    }

    func toggleActive(_ budget: LocalBudget, active: Bool, in ctx: ModelContext) async throws {
        let userId = try await client.auth.session.user.id
        struct Body: Encodable { let active: Bool }
        let remote: RemoteBudget = try await client
            .from("budgets")
            .update(Body(active: active))
            .eq("id", value: budget.serverId)
            .eq("user_id", value: userId.uuidString)
            .select("*, categories(id, name, icon, color)").single().execute().value
        budget.update(from: remote)
        try ctx.save()
    }

    func delete(_ budget: LocalBudget, in ctx: ModelContext) async throws {
        let userId = try await client.auth.session.user.id
        try await client.from("budgets").delete()
            .eq("id", value: budget.serverId)
            .eq("user_id", value: userId.uuidString)
            .execute()
        ctx.delete(budget)
        try ctx.save()
    }

    private func monthString(from date: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        let first = cal.date(from: comps)!
        return LedgerDate.dayFormatter.string(from: first)
    }
}
