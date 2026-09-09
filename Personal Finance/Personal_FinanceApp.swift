import SwiftUI
import SwiftData

@main
struct Personal_FinanceApp: App {
    let modelContainer: ModelContainer = {
        let schema = Schema([
            LocalWallet.self,
            LocalCategory.self,
            LocalTransaction.self,
            LocalBudget.self,
            LocalDebt.self,
            LocalSavingGoal.self,
            LocalRecurringTransaction.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUnlessOpen],
                ofItemAtPath: config.url.path
            )
            return container
        } catch {
            // Migration failed (schema change) — wipe local cache; data re-syncs from Supabase
            try? FileManager.default.removeItem(at: config.url)
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}
