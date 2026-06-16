import Foundation
import SwiftData

@MainActor
final class BudgetService {
    static let shared = BudgetService()
    private let client = SupabaseService.shared.client
    private init() {}

    private let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    func create(categoryId: UUID?, amount: Double, month: Date, in ctx: ModelContext) async throws {
        let userId = try await client.auth.session.user.id
        let monthStr = monthString(from: month)
        struct Body: Encodable {
            let user_id: String, category_id: String?, amount: Double, month: String
        }
        let remote: RemoteBudget = try await client
            .from("budgets")
            .insert(Body(user_id: userId.uuidString, category_id: categoryId?.uuidString,
                         amount: amount, month: monthStr))
            .select("*, categories(id, name, icon, color)").single().execute().value
        ctx.insert(LocalBudget(from: remote))
        try ctx.save()
    }

    func update(_ budget: LocalBudget, amount: Double, in ctx: ModelContext) async throws {
        struct Body: Encodable { let amount: Double }
        let remote: RemoteBudget = try await client
            .from("budgets")
            .update(Body(amount: amount))
            .eq("id", value: budget.serverId)
            .select("*, categories(id, name, icon, color)").single().execute().value
        budget.update(from: remote)
        try ctx.save()
    }

    func delete(_ budget: LocalBudget, in ctx: ModelContext) async throws {
        try await client.from("budgets").delete().eq("id", value: budget.serverId).execute()
        ctx.delete(budget)
        try ctx.save()
    }

    private func monthString(from date: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        let first = cal.date(from: comps)!
        return df.string(from: first)
    }
}
