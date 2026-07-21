import SwiftUI

enum NotifSeverity: Int {
    case alert = 0, warning, info, success

    var color: Color {
        switch self {
        case .alert:   return .expense
        case .warning: return .orange
        case .info:    return .blue
        case .success: return .income
        }
    }

    var icon: String {
        switch self {
        case .alert:   return "exclamationmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info:    return "bell.fill"
        case .success: return "checkmark.circle.fill"
        }
    }
}

enum NotifDestination {
    case budgets, debts, recurring, savingGoals, wallets

    var label: String {
        switch self {
        case .budgets:     return "Budgets"
        case .debts:       return "Debts"
        case .recurring:   return "Recurring"
        case .savingGoals: return "Goals"
        case .wallets:     return "Wallets"
        }
    }
}

struct AppNotification: Identifiable {
    let id: String
    let type: String
    let severity: NotifSeverity
    let title: String
    let message: String
    let destination: NotifDestination
    var isRead: Bool
}
