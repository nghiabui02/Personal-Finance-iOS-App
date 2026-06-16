import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Overview", systemImage: "chart.pie.fill")
                }
        }
    }
}
