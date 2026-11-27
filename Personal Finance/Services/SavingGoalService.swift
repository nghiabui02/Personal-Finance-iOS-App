import Foundation
import SwiftData

@MainActor
final class SavingGoalService {
    static let shared = SavingGoalService()
    private init() {}

    func create(
        name: String, icon: String?, targetAmount: Decimal,
        deadline: Date?, note: String?, in ctx: ModelContext
    ) async throws {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let client = mutation.client
        struct Body: Encodable {
            let user_id: String, name: String, icon: String?
            let target_amount: Decimal, current_amount: Decimal
            let deadline: String?, note: String?, status: GoalStatus
        }
        let remote: RemoteSavingGoal = try await client
            .from("saving_goals")
            .insert(Body(
                user_id: mutation.userId.uuidString, name: name, icon: icon,
                target_amount: targetAmount, current_amount: 0,
                deadline: deadline.map { LedgerDate.dayFormatter.string(from: $0) },
                note: note?.isEmpty == true ? nil : note,
                status: .active
            ))
            .select().single().execute().value
        try LocalDataStore.validate(mutation.session)
        ctx.insert(LocalSavingGoal(from: remote))
        try LocalDataStore.saveMutation(in: ctx)
    }

    func update(
        _ goal: LocalSavingGoal, name: String, icon: String?,
        targetAmount: Decimal, deadline: Date?, note: String?,
        in ctx: ModelContext
    ) async throws {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let client = mutation.client
        let remote: RemoteSavingGoal = try await client
            .from("saving_goals")
            .update(GoalUpdate(name: name, icon: icon, target_amount: targetAmount,
                               deadline: deadline.map { LedgerDate.string(from: $0) },
                               note: note?.isEmpty == true ? nil : note))
            .eq("id", value: goal.serverId)
            .eq("user_id", value: mutation.userId.uuidString)
            .select().single().execute().value
        try LocalDataStore.validate(mutation.session)
        goal.update(from: remote)
        try LocalDataStore.saveMutation(in: ctx)
    }

    func addContribution(_ goal: LocalSavingGoal, amount: Decimal, in ctx: ModelContext) async throws {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let client = mutation.client
        guard amount.isFinite, amount > 0 else {
            throw BusinessRuleError(message: "Enter a positive contribution.")
        }
        struct Params: Encodable { let p_goal_id: UUID; let p_amount: Decimal }
        let function = "contribute_to_saving_goal"
        let params = Params(p_goal_id: goal.serverId, p_amount: amount)
        let requestId = try ClientRequestID.id(for: function, userId: mutation.userId, params: params)
        let remote: RemoteSavingGoal? = try await client
            .rpc(function, params: ClientRequestParams(params: params, clientRequestId: requestId))
            .execute().value
        ClientRequestID.finish(function)
        guard let remote else {
            throw BusinessRuleError(message: "This goal is no longer active. Refresh and try again.")
        }
        try LocalDataStore.validate(mutation.session)
        goal.update(from: remote)
        try LocalDataStore.saveMutation(in: ctx)
    }

    func delete(_ goal: LocalSavingGoal, in ctx: ModelContext) async throws {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let client = mutation.client
        try await client.from("saving_goals").delete()
            .eq("id", value: goal.serverId)
            .eq("user_id", value: mutation.userId.uuidString)
            .execute()
        try LocalDataStore.validate(mutation.session)
        ctx.delete(goal)
        try LocalDataStore.saveMutation(in: ctx)
    }
}

/// The editable fields of a goal. A cleared field must reach the server as an explicit
/// `null`; synthesized encoding would drop the key and keep the old value.
struct GoalUpdate: Encodable {
    let name: String
    let icon: String?
    let target_amount: Decimal
    let deadline: String?
    let note: String?

    private enum CodingKeys: String, CodingKey {
        case name, icon, target_amount, deadline, note
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(icon, forKey: .icon)
        try container.encode(target_amount, forKey: .target_amount)
        try container.encode(deadline, forKey: .deadline)
        try container.encode(note, forKey: .note)
    }
}
