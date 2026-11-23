import Foundation
import Supabase
import SwiftData

@MainActor
final class CategoryService {
    static let shared = CategoryService()
    private init() {}

    func ensureSystemCategory(_ systemKey: String, using client: PostgrestClient) async throws -> UUID {
        try await client.rpc("ensure_system_category", params: ["p_key": systemKey]).execute().value
    }

    func create(name: String, type: String, icon: String?, color: String?, in ctx: ModelContext) async throws {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        struct Body: Encodable {
            let user_id: UUID, name: String, type: String, icon: String?, color: String?
        }
        let remote: RemoteCategory = try await mutation.client
            .from("user_categories")
            .insert(Body(user_id: mutation.userId, name: name, type: type, icon: icon, color: color))
            .select(CategoryProjection.membership).single().execute().value
        try LocalDataStore.validate(mutation.session)
        ctx.insert(LocalCategory(from: remote))
        try LocalDataStore.saveMutation(in: ctx)
    }

    func update(_ cat: LocalCategory, name: String, icon: String?, color: String?, in ctx: ModelContext) async throws {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let remote: RemoteCategory = try await mutation.client
            .from("user_categories")
            .update(["name": name, "icon": icon, "color": color])
            .eq("id", value: cat.serverId)
            .eq("user_id", value: mutation.userId)
            .select(CategoryProjection.membership).single().execute().value
        try LocalDataStore.validate(mutation.session)
        cat.update(from: remote)
        try LocalDataStore.saveMutation(in: ctx)
    }

    func delete(_ cat: LocalCategory, in ctx: ModelContext) async throws {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let _: RemoteCategory = try await mutation.client
            .from("user_categories")
            .update(["is_active": false])
            .eq("id", value: cat.serverId)
            .eq("user_id", value: mutation.userId)
            .select(CategoryProjection.membership).single().execute().value
        try LocalDataStore.validate(mutation.session)
        ctx.delete(cat)
        try LocalDataStore.saveMutation(in: ctx)
    }
}
