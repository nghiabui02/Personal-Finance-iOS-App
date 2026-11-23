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
    let creditLimit: Double?
    let statementDay: Int?
    let paymentDueDay: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, type, balance, color, icon
        case isDefault = "is_default"
        case updatedAt = "updated_at"
        case creditLimit = "credit_limit"
        case statementDay = "statement_day"
        case paymentDueDay = "payment_due_day"
    }
}

enum CategoryProjection {
    static let template = "template:categories(default_key,name_en,name_vi)"
    static let membership = "*,\(template)"
    static let joined = "categories:user_categories(id,name,icon,color,system_key,is_active,\(template))"
    static let withWallet = "*,\(joined),wallets(id,name)"
    static let withCategory = "*,\(joined)"
}

struct CategoryTemplate: Codable {
    let defaultKey: String
    let nameEN: String?
    let nameVI: String?

    enum CodingKeys: String, CodingKey {
        case defaultKey = "default_key"
        case nameEN = "name_en"
        case nameVI = "name_vi"
    }
}

struct CategoryReference: Codable {
    let id: UUID
    let name: String?
    let icon: String?
    let color: String?
    let systemKey: String?
    let isActive: Bool
    let template: CategoryTemplate?

    enum CodingKeys: String, CodingKey {
        case id, name, icon, color, template
        case systemKey = "system_key"
        case isActive = "is_active"
    }

    var displayName: String {
        categoryLabel(name: name, systemKey: systemKey, template: template)
    }
}

struct RemoteCategory: Codable, Identifiable {
    let id: UUID
    let name: String?
    let type: String
    let icon: String?
    let color: String?
    let templateId: UUID?
    let systemKey: String?
    let isActive: Bool
    let template: CategoryTemplate?

    enum CodingKeys: String, CodingKey {
        case id, name, type, icon, color, template
        case templateId = "category_id"
        case systemKey = "system_key"
        case isActive = "is_active"
    }

    var isDefault: Bool { templateId != nil || systemKey != nil }

    var displayName: String {
        categoryLabel(name: name, systemKey: systemKey, template: template)
    }
}

private func categoryLabel(name: String?, systemKey: String?, template: CategoryTemplate?) -> String {
    if let name { return name }
    switch systemKey {
    case SystemCategory.lendOut: return "Money Lent"
    case SystemCategory.borrowIn: return "Money Borrowed"
    case SystemCategory.collectDebt: return "Debt Collection"
    case SystemCategory.repayDebt: return "Debt Repayment"
    case SystemCategory.adjustUp, SystemCategory.adjustDown: return "Balance Adjustment"
    default:
        return template?.nameEN ?? template?.nameVI
            ?? template?.defaultKey.replacingOccurrences(of: "_", with: " ").capitalized
            ?? "Category"
    }
}

struct RemoteNetWorthSnapshot: Codable, Identifiable {
    let id: UUID
    let recordedDate: String
    let netWorth: Double

    enum CodingKeys: String, CodingKey {
        case id
        case recordedDate = "recorded_date"
        case netWorth = "net_worth"
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
    let bankFee: Double?
    // Joined via .select("*, categories(...), wallets(...)")
    let categories: CategoryReference?
    let wallets: WalletInfo?

    struct WalletInfo: Codable {
        let id: UUID
        let name: String
    }

    let debtPaymentId: UUID?

    enum CodingKeys: String, CodingKey {
        case id, note, amount, type, categories, wallets
        case walletId = "wallet_id"
        case categoryId = "user_category_id"
        case transactionDate = "transaction_date"
        case updatedAt = "updated_at"
        case transferPairId = "transfer_pair_id"
        case debtPaymentId = "debt_payment_id"
        case bankFee = "bank_fee"
    }
}

struct RemoteBudget: Codable, Identifiable {
    let id: UUID
    let categoryId: UUID?
    let amount: Double
    let month: String                 // "YYYY-MM-01"
    let rollover: Bool
    let active: Bool
    let categories: CategoryReference?

    enum CodingKeys: String, CodingKey {
        case id, amount, month, categories, rollover, active
        case categoryId = "user_category_id"
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
    let type: String?

    enum CodingKeys: String, CodingKey {
        case id, amount, note, type
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
    let categories: CategoryReference?
    let wallets: WalletInfo?

    struct WalletInfo: Codable {
        let id: UUID
        let name: String
    }

    let active: Bool
    /// NULL when the rule has no fee — the server stores `bank_fee > 0 ? fee : null`.
    let bankFee: Double?

    enum CodingKeys: String, CodingKey {
        case id, note, amount, type, frequency, categories, wallets, active
        case walletId = "wallet_id"
        case categoryId = "user_category_id"
        case startDate = "start_date"
        case endDate = "end_date"
        case nextRunDate = "next_run_date"
        case updatedAt = "updated_at"
        case bankFee = "bank_fee"
    }
}
