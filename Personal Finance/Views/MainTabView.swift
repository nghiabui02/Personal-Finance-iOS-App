import SwiftUI

struct MainTabView: View {
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
    }
}
