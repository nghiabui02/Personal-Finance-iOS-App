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
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
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
