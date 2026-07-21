import Foundation
import SwiftData

@MainActor
final class SavingGoalService {
    static let shared = SavingGoalService()
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
        name: String, icon: String?, targetAmount: Double,
        deadline: Date?, note: String?, in ctx: ModelContext
    ) async throws {
        let userId = try await client.auth.session.user.id
        struct Body: Encodable {
            let user_id: String, name: String, icon: String?
            let target_amount: Double, current_amount: Double
            let deadline: String?, note: String?, status: String
        }
        let remote: RemoteSavingGoal = try await client
            .from("saving_goals")
            .insert(Body(
                user_id: userId.uuidString, name: name, icon: icon,
                target_amount: targetAmount, current_amount: 0,
                deadline: deadline.map { df.string(from: $0) },
                note: note?.isEmpty == true ? nil : note,
                status: "active"
            ))
            .select().single().execute().value
        ctx.insert(LocalSavingGoal(from: remote))
        try ctx.save()
    }

    func update(
        _ goal: LocalSavingGoal, name: String, icon: String?,
        targetAmount: Double, deadline: Date?, note: String?,
        in ctx: ModelContext
    ) async throws {
        let userId = try await client.auth.session.user.id
        struct Body: Encodable {
            let name: String, icon: String?, target_amount: Double, deadline: String?, note: String?
        }
        let remote: RemoteSavingGoal = try await client
            .from("saving_goals")
            .update(Body(name: name, icon: icon, target_amount: targetAmount,
                        deadline: deadline.map { df.string(from: $0) },
                        note: note?.isEmpty == true ? nil : note))
            .eq("id", value: goal.serverId)
            .eq("user_id", value: userId.uuidString)
            .select().single().execute().value
        goal.update(from: remote)
        try ctx.save()
    }

    func addContribution(_ goal: LocalSavingGoal, amount: Double, in ctx: ModelContext) async throws {
        let userId = try await client.auth.session.user.id
        let newAmount = goal.currentAmount + amount
        let newStatus = newAmount >= goal.targetAmount ? "completed" : goal.status
        struct Body: Encodable { let current_amount: Double, status: String }
        let remote: RemoteSavingGoal = try await client
            .from("saving_goals")
            .update(Body(current_amount: newAmount, status: newStatus))
            .eq("id", value: goal.serverId)
            .eq("user_id", value: userId.uuidString)
            .select().single().execute().value
        goal.update(from: remote)
        try ctx.save()
    }

    func delete(_ goal: LocalSavingGoal, in ctx: ModelContext) async throws {
        let userId = try await client.auth.session.user.id
        try await client.from("saving_goals").delete()
            .eq("id", value: goal.serverId)
            .eq("user_id", value: userId.uuidString)
            .execute()
        ctx.delete(goal)
        try ctx.save()
    }
}
