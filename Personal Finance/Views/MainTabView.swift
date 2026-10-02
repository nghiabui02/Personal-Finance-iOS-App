import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var tabRouter = AppTabRouter()
    @StateObject private var sync = SyncManager.shared

    var body: some View {
        tabs
            .safeAreaInset(edge: .top) { offlineBanner }
            .animation(.easeInOut(duration: 0.2), value: sync.isOnline)
    }

    /// Recording anything needs the server, so the whole app is read-only while
    /// offline. Saying so up front beats letting each save fail on its own.
    @ViewBuilder
    private var offlineBanner: some View {
        if !sync.isOnline {
            Label("Offline — showing saved data. You can't record changes.", systemImage: "wifi.slash")
                .font(.caption)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.expense)
        }
    }

    private var tabs: some View {
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
