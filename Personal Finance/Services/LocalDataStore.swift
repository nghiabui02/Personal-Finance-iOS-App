import Foundation
import Supabase
import SwiftData

@MainActor
enum LocalDataStore {
    struct Session: Equatable {
        let userId: UUID
        let generation = UUID()
    }

    struct Mutation {
        let session: Session
        let client: PostgrestClient
        var userId: UUID { session.userId }
    }

    private static let ownerKey = "pf_active_local_user_id"
    private static let auth = SupabaseService.shared.client.auth

    private(set) static var session: Session?
    private(set) static var revision = 0
    private(set) static var isMutating = false

    static func prepare(for userId: UUID?, in context: ModelContext) throws {
        guard session?.userId != userId || userId == nil else { return }
        session = nil
        isMutating = false
        SyncManager.shared.clearSyncState()
        let owner = userId?.uuidString.lowercased()
        let defaults = UserDefaults.standard
        if owner == nil || owner != defaults.string(forKey: ownerKey) {
            do {
                try clearLedger(in: context)
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
            defaults.set(owner, forKey: ownerKey)
        }
        CategoryDirectory.shared.prepare(for: userId)
        session = userId.map { Session(userId: $0) }
    }

    private static func clearLedger(in context: ModelContext) throws {
        try context.delete(model: LocalTransaction.self)
        try context.delete(model: LocalBudget.self)
        try context.delete(model: LocalDebt.self)
        try context.delete(model: LocalSavingGoal.self)
        try context.delete(model: LocalRecurringTransaction.self)
        try context.delete(model: LocalWallet.self)
        try context.delete(model: LocalCategory.self)
    }

    static func validate(_ expected: Session) throws {
        guard session == expected, auth.currentSession?.user.id == expected.userId else {
            throw CancellationError()
        }
    }

    static func authenticatedClient(for expected: Session) async throws -> PostgrestClient {
        try validate(expected)
        let credentials = try await auth.session
        try validate(expected)
        guard credentials.user.id == expected.userId else { throw CancellationError() }
        let service = SupabaseService.shared
        var headers = service.client.headers.filter { $0.key.caseInsensitiveCompare("Authorization") != .orderedSame }
        // Keep this request tied to the account that started it, even if the shared auth session changes.
        headers["Authorization"] = "Bearer \(credentials.accessToken)"
        return PostgrestClient(
            url: service.databaseURL,
            headers: headers,
            retryEnabled: false
        )
    }

    static func beginMutation() async throws -> Mutation {
        guard let session else {
            throw BusinessRuleError(message: "Sync your data before recording changes.")
        }
        guard !isMutating else {
            throw BusinessRuleError(message: "Wait for the current change to finish.")
        }
        try validate(session)
        isMutating = true
        revision += 1
        do {
            return Mutation(session: session, client: try await authenticatedClient(for: session))
        } catch {
            endMutation(session)
            throw error
        }
    }

    static func endMutation(_ expected: Session) {
        guard session == expected else { return }
        isMutating = false
        SyncManager.shared.resumePendingSync()
    }

    static func saveMutation(in context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            SyncManager.shared.requestSync(modelContext: context)
            throw BusinessRuleError(message: "The server saved the change. The app will refresh its local copy.")
        }
    }
}
