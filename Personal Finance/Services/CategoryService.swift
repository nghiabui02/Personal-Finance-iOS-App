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
        let userId = try await client.auth.session.user.id
        struct Body: Encodable { let name: String, icon: String?, color: String? }
        let remote: RemoteCategory = try await client
            .from("categories")
            .update(Body(name: name, icon: icon, color: color))
            .eq("id", value: cat.serverId)
            .eq("user_id", value: userId.uuidString)
            .select().single().execute().value
        cat.update(from: remote)
        try ctx.save()
    }

    func delete(_ cat: LocalCategory, in ctx: ModelContext) async throws {
        let userId = try await client.auth.session.user.id
        try await client.from("categories").delete()
            .eq("id", value: cat.serverId)
            .eq("user_id", value: userId.uuidString)
            .execute()
        ctx.delete(cat)
        try ctx.save()
    }

    func sync(in ctx: ModelContext) async throws {
        let userId = try await client.auth.session.user.id
        let remotes: [RemoteCategory] = try await client
            .from("categories")
            .select()
            .or("user_id.is.null,user_id.eq.\(userId.uuidString)")
            .execute().value
        let ids = remotes.map { $0.id }
        let desc = FetchDescriptor<LocalCategory>(
            predicate: #Predicate<LocalCategory> { ids.contains($0.serverId) }
        )
        let existing = (try? ctx.fetch(desc)) ?? []
        let map = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })
        for r in remotes {
            if let local = map[r.id] { local.update(from: r) }
            else { ctx.insert(LocalCategory(from: r)) }
        }
        try ctx.save()
    }
}
