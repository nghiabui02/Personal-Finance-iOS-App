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
                [.protectionKey: FileAttributeProtectionType.completeUnlessOpen],
                ofItemAtPath: config.url.path
            )
            return container
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}
