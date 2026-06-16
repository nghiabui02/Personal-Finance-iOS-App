import Foundation

struct RemoteWallet: Codable, Identifiable {
    let id: String
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
    let id: String
    let name: String
    let type: String
    let icon: String?
    let color: String?
}

struct RemoteTransaction: Codable, Identifiable {
    let id: String
    let walletId: String?             // nullable — on delete set null
    let categoryId: String?
    let type: String
    let amount: Double
    let note: String?
    let transactionDate: String       // PostgreSQL date → "2026-06-16"
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case walletId = "wallet_id"
        case categoryId = "category_id"
        case type, amount, note
        case transactionDate = "transaction_date"
        case updatedAt = "updated_at"
    }
}

struct RemoteBudget: Codable, Identifiable {
    let id: String
    let categoryId: String?           // nullable — on delete cascade
    let amount: Double
    let month: String                 // PostgreSQL date → "2026-06-01"

    enum CodingKeys: String, CodingKey {
        case id, amount, month
        case categoryId = "category_id"
    }
}
