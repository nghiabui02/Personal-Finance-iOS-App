import SwiftUI

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var tabRouter = AppTabRouter()

    var body: some View {
        TabView(selection: $tabRouter.selectedTab) {
            DashboardView()
                .tabItem { Label("Overview", systemImage: "chart.pie.fill") }
                .tag(AppTab.overview)

            TransactionsView()
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.transactions)

            ReportsView()
                .tabItem { Label("Reports", systemImage: "chart.bar.fill") }
                .tag(AppTab.reports)

            WalletsView()
                .tabItem { Label("Wallets", systemImage: "creditcard.fill") }
                .tag(AppTab.wallets)

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                .tag(AppTab.more)
        }
        .environmentObject(tabRouter)
        .onReceive(NotificationCenter.default.publisher(for: .networkRestored)) { _ in
            Task { await SyncManager.shared.syncAll(modelContext: modelContext) }
        }
    }
}
