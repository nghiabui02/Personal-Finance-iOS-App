import Foundation
import SwiftData

enum LocalDataStore {
    private static let activeUserIdKey = "pf_active_local_user_id"

    static func prepareForAuthenticatedUser(
        _ userId: UUID,
        in context: ModelContext
    ) {
        let nextUserId = userId.uuidString.lowercased()
        let previousUserId = UserDefaults.standard.string(forKey: activeUserIdKey)

        guard previousUserId != nextUserId else { return }

        clearAll(in: context)

        UserDefaults.standard.set(nextUserId, forKey: activeUserIdKey)
    }

    static func clearForSignedOutUser(in context: ModelContext) {
        clearAll(in: context)
        UserDefaults.standard.removeObject(forKey: activeUserIdKey)
    }

    static func clearAll(in context: ModelContext) {
        delete(LocalTransaction.self, in: context)
        delete(LocalBudget.self, in: context)
        delete(LocalDebt.self, in: context)
        delete(LocalSavingGoal.self, in: context)
        delete(LocalRecurringTransaction.self, in: context)
        delete(LocalWallet.self, in: context)
        delete(LocalCategory.self, in: context)
        try? context.save()
    }

    private static func delete<T: PersistentModel>(
        _ modelType: T.Type,
        in context: ModelContext
    ) {
        let descriptor = FetchDescriptor<T>()
        let items = (try? context.fetch(descriptor)) ?? []
        for item in items {
            context.delete(item)
        }
    }
}
