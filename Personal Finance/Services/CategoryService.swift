import Foundation
import Supabase
import SwiftData

struct CategoryDependencies: Identifiable {
    let id: UUID
    let budgets: [RemoteBudget]
    let recurring: [RemoteRecurringTransaction]

    var isEmpty: Bool { budgets.isEmpty && recurring.isEmpty }
}

@MainActor
final class CategoryService {
    static let shared = CategoryService()
    private init() {}

    func ensureSystemCategory(_ systemKey: String, using client: PostgrestClient) async throws -> UUID {
        try await client.rpc("ensure_system_category", params: ["p_key": systemKey]).execute().value
    }

    func catalog() async throws -> [CategoryCatalogTemplate] {
        guard let session = LocalDataStore.session else { throw CancellationError() }
        let client = try await LocalDataStore.authenticatedClient(for: session)
        let rows: [CategoryCatalogTemplate] = try await client.readRows {
            client.from("categories").select(CategoryCatalogTemplate.columns).eq("is_available", value: true)
        }
        try LocalDataStore.validate(session)
        return rows
    }

    func adopt(_ templates: [CategoryCatalogTemplate], in context: ModelContext) async throws {
        guard !templates.isEmpty else { return }
        let selected = Dictionary(templates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let rows: [RemoteCategory] = try await mutation.client
            .rpc("adopt_categories", params: ["p_template_ids": Array(selected.keys)]).execute().value
        let memberships = rows.map { row in
            RemoteCategory(
                id: row.id, name: row.name, type: row.type, icon: row.icon, color: row.color,
                templateId: row.templateId, systemKey: row.systemKey, isActive: row.isActive,
                template: row.templateId.flatMap { selected[$0]?.labels } ?? row.template
            )
        }
        try apply(memberships, for: mutation, in: context)
    }

    func dependencies(for category: LocalCategory) async throws -> CategoryDependencies {
        guard let session = LocalDataStore.session else { throw CancellationError() }
        let id = category.serverId
        let client = try await LocalDataStore.authenticatedClient(for: session)
        let now = Date()
        let month = LedgerDate.string(from: LedgerDate.startOfMonth(for: now) ?? now)
        async let budgets: [RemoteBudget] = client.readRows {
            client.from("budgets").select()
                .eq("user_id", value: session.userId).eq("user_category_id", value: id)
                .eq("active", value: true).eq("month", value: month)
        }
        async let recurring: [RemoteRecurringTransaction] = client.readRows {
            client.from("recurring_transactions").select()
                .eq("user_id", value: session.userId).eq("user_category_id", value: id).eq("active", value: true)
        }
        let result = try await CategoryDependencies(id: id, budgets: budgets, recurring: recurring)
        try LocalDataStore.validate(session)
        return result
    }

    func create(name: String, type: TransactionKind, icon: String?, color: String?, in context: ModelContext) async throws {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let values: [String: AnyJSON] = [
            "user_id": .string(mutation.userId.uuidString), "name": .string(name), "type": .string(type.rawValue),
            "icon": icon.map(AnyJSON.string) ?? .null, "color": color.map(AnyJSON.string) ?? .null
        ]
        let row: RemoteCategory = try await mutation.client
            .from("user_categories").insert(values)
            .select(CategoryProjection.membership).single().execute().value
        try apply([row], for: mutation, in: context)
    }

    func update(_ category: LocalCategory, name: String?, icon: String?, color: String?, in context: ModelContext)
        async throws {
        try await patch(
            category,
            values: [
                "name": name.map(AnyJSON.string) ?? .null, "icon": icon.map(AnyJSON.string) ?? .null,
                "color": color.map(AnyJSON.string) ?? .null
            ], in: context)
    }

    func setActive(_ category: LocalCategory, _ active: Bool, in context: ModelContext) async throws {
        try await patch(category, values: ["is_active": .bool(active)], in: context)
    }

    private func patch(_ category: LocalCategory, values: [String: AnyJSON], in context: ModelContext) async throws {
        let id = category.serverId
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let row: RemoteCategory = try await mutation.client
            .from("user_categories").update(values)
            .eq("id", value: id).eq("user_id", value: mutation.userId)
            .select(CategoryProjection.membership).single().execute().value
        try apply([row], for: mutation, in: context)
    }

    private func apply(_ rows: [RemoteCategory], for mutation: LocalDataStore.Mutation, in context: ModelContext) throws {
        try LocalDataStore.validate(mutation.session)
        let ids = rows.map(\.id)
        let cached = try context.fetch(
            FetchDescriptor<LocalCategory>(predicate: #Predicate { ids.contains($0.serverId) }))
        let byID = Dictionary(cached.map { ($0.serverId, $0) }, uniquingKeysWith: { first, _ in first })
        for row in rows {
            if let local = byID[row.id] { local.update(from: row) } else { context.insert(LocalCategory(from: row)) }
        }
        try LocalDataStore.saveMutation(in: context)
        CategoryDirectory.shared.merge(rows)
    }
}
