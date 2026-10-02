import Foundation
import Supabase
import SwiftData

@MainActor
final class CategoryService {
    static let shared = CategoryService()
    private let client = SupabaseService.shared.client
    private init() {}

    /// Returns the server-owned category for `systemKey`, creating it on first use.
    ///
    /// These are not seeded with an account — they appear the first time a feature
    /// needs one, so a user who has never reconciled a wallet has no adjustment
    /// category yet. Looking only at the local store would fail that first attempt
    /// with nothing the user could do about it.
    func ensureSystemCategory(
        _ systemKey: String, type: String, name: String, icon: String, color: String,
        in ctx: ModelContext
    ) async throws -> LocalCategory {
        let existing = (try? ctx.fetch(FetchDescriptor<LocalCategory>())) ?? []
        if let local = existing.first(where: { $0.systemKey == systemKey }) { return local }

        let userId = try await client.auth.session.user.id

        // Far more common than a race: the category exists server-side but this
        // device has not synced it yet.
        if let found = try await fetchSystemCategory(systemKey, userId: userId) {
            return store(found, in: ctx)
        }

        struct Body: Encodable {
            let user_id: String, name: String, type: String
            let icon: String, color: String, system_key: String
        }
        do {
            let remote: RemoteCategory = try await client
                .from("categories")
                .insert(Body(user_id: userId.uuidString, name: name, type: type,
                             icon: icon, color: color, system_key: systemKey))
                .select().single().execute().value
            return store(remote, in: ctx)
        } catch let error as PostgrestError where error.code == "23505" {
            // Another device created it between the lookup and this insert. A
            // partial unique index on (user_id, system_key) makes that a rejected
            // insert rather than a duplicate row, so re-reading is enough.
            guard let found = try await fetchSystemCategory(systemKey, userId: userId) else {
                throw error
            }
            return store(found, in: ctx)
        }
    }

    private func fetchSystemCategory(_ systemKey: String, userId: UUID) async throws -> RemoteCategory? {
        let remotes: [RemoteCategory] = try await client
            .from("categories")
            .select()
            .eq("user_id", value: userId)
            .eq("system_key", value: systemKey)
            .limit(1)
            .execute().value
        return remotes.first
    }

    private func store(_ remote: RemoteCategory, in ctx: ModelContext) -> LocalCategory {
        let local = LocalCategory(from: remote)
        ctx.insert(local)
        try? ctx.save()
        return local
    }

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
        let map = Dictionary(existing.map { ($0.serverId, $0) }, uniquingKeysWith: { first, _ in first })
        for r in remotes {
            if let local = map[r.id] { local.update(from: r) }
            else { ctx.insert(LocalCategory(from: r)) }
        }
        try ctx.save()
    }
}
