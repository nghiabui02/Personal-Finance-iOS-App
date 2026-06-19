import Foundation

struct RemoteWallet: Codable, Identifiable {
    let id: UUID
    let name: String
    let type: String
    let balance: Double
    let isDefault: Bool
    let color: String?
    let icon: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, type, balance, color, icon
        case isDefault = "is_default"
        case updatedAt = "updated_at"
    }
}

struct RemoteCategory: Codable, Identifiable {
    let id: UUID
    let name: String
    let type: String
    let icon: String?
    let color: String?
    let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, type, icon, color
        case isDefault = "is_default"
    }
}

struct RemoteTransaction: Codable, Identifiable {
    let id: UUID
    let walletId: UUID?
    let categoryId: UUID?
    let type: String
    let amount: Double
    let note: String?
    let transactionDate: String       // "YYYY-MM-DD"
    let updatedAt: Date
    let transferPairId: UUID?
    // Joined via .select("*, categories(...), wallets(...)")
    let categories: CategoryInfo?
    let wallets: WalletInfo?

    struct CategoryInfo: Codable {
        let id: UUID
        let name: String
        let icon: String?
        let color: String?
    }

    struct WalletInfo: Codable {
        let id: UUID
        let name: String
    }

    enum CodingKeys: String, CodingKey {
        case id, note, amount, type, categories, wallets
        case walletId = "wallet_id"
        case categoryId = "category_id"
        case transactionDate = "transaction_date"
        case updatedAt = "updated_at"
        case transferPairId = "transfer_pair_id"
    }
}

struct RemoteBudget: Codable, Identifiable {
    let id: UUID
    let categoryId: UUID?
    let amount: Double
    let month: String                 // "YYYY-MM-01"
    // Joined via .select("*, categories(...)")
    let categories: CategoryInfo?

    struct CategoryInfo: Codable {
        let id: UUID
        let name: String
        let icon: String?
        let color: String?
    }

    enum CodingKeys: String, CodingKey {
        case id, amount, month, categories
        case categoryId = "category_id"
    }
}

struct RemoteDebt: Codable, Identifiable {
    let id: UUID
    let walletId: UUID?
    let type: String
    let personName: String
    let personContact: String?
    let amount: Double
    let remainingAmount: Double
    let dueDate: String?
    let status: String
    let note: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, type, note, status, amount
        case walletId = "wallet_id"
        case personName = "person_name"
        case personContact = "person_contact"
        case remainingAmount = "remaining_amount"
        case dueDate = "due_date"
        case updatedAt = "updated_at"
    }
}

struct RemoteDebtPayment: Codable, Identifiable {
    let id: UUID
    let debtId: UUID
    let amount: Double
    let note: String?
    let paidAt: Date

    enum CodingKeys: String, CodingKey {
        case id, amount, note
        case debtId = "debt_id"
        case paidAt = "paid_at"
    }
}

struct RemoteSavingGoal: Codable, Identifiable {
    let id: UUID
    let name: String
    let icon: String?
    let targetAmount: Double
    let currentAmount: Double
    let deadline: String?
    let status: String
    let note: String?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, icon, note, status
        case targetAmount = "target_amount"
        case currentAmount = "current_amount"
        case deadline
        case updatedAt = "updated_at"
    }
}

struct RemoteRecurringTransaction: Codable, Identifiable {
    let id: UUID
    let walletId: UUID?
    let categoryId: UUID?
    let type: String
    let amount: Double
    let note: String?
    let frequency: String
    let startDate: String
    let endDate: String?
    let nextRunDate: String?
    let updatedAt: Date
    let categories: CategoryInfo?
    let wallets: WalletInfo?

    struct CategoryInfo: Codable {
        let id: UUID
        let name: String
        let icon: String?
        let color: String?
    }

    struct WalletInfo: Codable {
        let id: UUID
        let name: String
    }

    enum CodingKeys: String, CodingKey {
        case id, note, amount, type, frequency, categories, wallets
        case walletId = "wallet_id"
        case categoryId = "category_id"
        case startDate = "start_date"
        case endDate = "end_date"
        case nextRunDate = "next_run_date"
        case updatedAt = "updated_at"
    }
}
