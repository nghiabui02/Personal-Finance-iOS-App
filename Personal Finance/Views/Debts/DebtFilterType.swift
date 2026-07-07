import SwiftUI

enum DebtFilterType: String, CaseIterable, Identifiable {
    case all = "All"
    case lend = "I Lend"
    case borrow = "I Borrow"

    var id: String { rawValue }

    var tintColor: Color {
        switch self {
        case .all:
            return .blue
        case .lend:
            return .lend
        case .borrow:
            return .borrow
        }
    }
}

enum DebtFilter {
    static func apply(_ filter: DebtFilterType, to debts: [LocalDebt]) -> [LocalDebt] {
        switch filter {
        case .all:
            return debts
        case .lend:
            return debts.filter { $0.type == "lend" }
        case .borrow:
            return debts.filter { $0.type == "borrow" }
        }
    }
}
