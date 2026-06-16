import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Overview", systemImage: "chart.pie.fill") }

            TransactionsView()
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }

            WalletsView()
                .tabItem { Label("Wallets", systemImage: "creditcard.fill") }
        }
    }
}
