import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var tabRouter = AppTabRouter()
    private var sync: SyncManager { .shared }

    var body: some View {
        tabs
            .safeAreaInset(edge: .top) { syncBanner }
            .animation(.easeInOut(duration: 0.2), value: sync.isOnline)
    }

    @ViewBuilder
    private var syncBanner: some View {
        if !sync.isOnline {
            banner("Offline — showing saved data.", symbol: "wifi.slash")
        } else if sync.syncError != nil {
            banner("Sync failed — saved data may be outdated.", symbol: "exclamationmark.arrow.trianglehead.clockwise.rotate.90")
        }
    }

    private func banner(_ text: LocalizedStringKey, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.expense)
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
        .task { await sync.syncAll(modelContext: modelContext) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { sync.requestSync(modelContext: modelContext) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .networkRestored)) { _ in
            sync.requestSync(modelContext: modelContext)
        }
    }
}
