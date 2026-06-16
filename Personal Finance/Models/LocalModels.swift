import Foundation
import SwiftData

private let yyyyMMdd: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

@Model
final class LocalWallet {
    var serverId: UUID
    var name: String
    var type: String
    var balance: Double
    var isDefault: Bool
    var color: String?
    var icon: String?
    var updatedAt: Date

    init(from r: RemoteWallet) {
        serverId = r.id; name = r.name; type = r.type
        balance = r.balance; isDefault = r.isDefault
        color = r.color; icon = r.icon; updatedAt = r.updatedAt
    }
    func update(from r: RemoteWallet) {
        name = r.name; type = r.type; balance = r.balance
        isDefault = r.isDefault; color = r.color; icon = r.icon
        updatedAt = r.updatedAt
    }
}

@Model
final class LocalCategory {
    var serverId: UUID
    var name: String
    var type: String
    var icon: String?
    var color: String?

    init(from r: RemoteCategory) {
        serverId = r.id; name = r.name; type = r.type
        icon = r.icon; color = r.color
    }
    func update(from r: RemoteCategory) {
        name = r.name; type = r.type; icon = r.icon; color = r.color
    }
}

@Model
final class LocalTransaction {
    var serverId: UUID
    var walletId: UUID?
    var walletName: String
    var categoryId: UUID?
    var categoryName: String?
    var categoryIcon: String?
    var categoryColor: String?
    var type: String
    var amount: Double
    var note: String?
    var transactionDate: Date
    var updatedAt: Date
    var syncStatus: String

    init(from r: RemoteTransaction) {
        serverId = r.id
        walletId = r.walletId
        walletName = r.wallets?.name ?? "Unknown Wallet"
        categoryId = r.categoryId
        categoryName = r.categories?.name
        categoryIcon = r.categories?.icon
        categoryColor = r.categories?.color
        type = r.type; amount = r.amount; note = r.note
        transactionDate = yyyyMMdd.date(from: r.transactionDate) ?? Date()
        updatedAt = r.updatedAt; syncStatus = "synced"
    }

    func update(from r: RemoteTransaction) {
        walletId = r.walletId
        walletName = r.wallets?.name ?? "Unknown Wallet"
        categoryId = r.categoryId
        categoryName = r.categories?.name
        categoryIcon = r.categories?.icon
        categoryColor = r.categories?.color
        type = r.type; amount = r.amount; note = r.note
        transactionDate = yyyyMMdd.date(from: r.transactionDate) ?? Date()
        updatedAt = r.updatedAt; syncStatus = "synced"
    }
}

@Model
final class LocalBudget {
    var serverId: UUID
    var categoryId: UUID?
    var categoryName: String
    var categoryIcon: String?
    var categoryColor: String?
    var amount: Double
    var month: Date

    init(from r: RemoteBudget) {
        serverId = r.id
        categoryId = r.categoryId
        categoryName = r.categories?.name ?? "Unknown"
        categoryIcon = r.categories?.icon
        categoryColor = r.categories?.color
        amount = r.amount
        month = yyyyMMdd.date(from: r.month) ?? Date()
    }

    func update(from r: RemoteBudget) {
        categoryId = r.categoryId
        categoryName = r.categories?.name ?? "Unknown"
        categoryIcon = r.categories?.icon
        categoryColor = r.categories?.color
        amount = r.amount
        month = yyyyMMdd.date(from: r.month) ?? Date()
    }
}
