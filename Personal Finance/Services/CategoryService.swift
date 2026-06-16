import Foundation
import SwiftData

@MainActor
final class CategoryService {
    static let shared = CategoryService()
    private let client = SupabaseService.shared.client
    private init() {}

    func create(name: String, type: String, icon: String?, color: String?, in ctx: ModelContext) async throws {
        let userId = try await client.auth.session.user.id
        struct Body: Encodable {
            let user_id: String, name: String, type: String, icon: String?, color: String?
        }
        let remote: RemoteCategory = try await client
            .from("categories")
            .insert(Body(user_id: userId.uuidString, name: name, type: type, icon: icon, color: color))
            .select().single().execute().value
        ctx.insert(LocalCategory(from: remote))
        try ctx.save()
    }

    func update(_ cat: LocalCategory, name: String, icon: String?, color: String?, in ctx: ModelContext) async throws {
        struct Body: Encodable { let name: String, icon: String?, color: String? }
        let remote: RemoteCategory = try await client
            .from("categories")
            .update(Body(name: name, icon: icon, color: color))
            .eq("id", value: cat.serverId)
            .select().single().execute().value
        cat.update(from: remote)
        try ctx.save()
    }

    func delete(_ cat: LocalCategory, in ctx: ModelContext) async throws {
        try await client.from("categories").delete().eq("id", value: cat.serverId).execute()
        ctx.delete(cat)
        try ctx.save()
    }
}
