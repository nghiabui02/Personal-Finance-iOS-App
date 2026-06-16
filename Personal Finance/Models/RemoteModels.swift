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
