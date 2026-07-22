import SwiftUI

enum AppTab: Int {
    case overview, transactions, reports, wallets, more
}

@MainActor
final class AppTabRouter: ObservableObject {
    @Published var selectedTab: AppTab = .overview
}
