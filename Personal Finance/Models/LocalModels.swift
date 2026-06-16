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
    var serverId: String
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
    var serverId: String
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
    var serverId: String
    var walletId: String
    var walletName: String
    var categoryId: String?
    var categoryName: String?
    var categoryIcon: String?
    var categoryColor: String?
    var type: String
    var amount: Double
    var note: String?
    var transactionDate: Date
    var updatedAt: Date
    var syncStatus: String

    init(from r: RemoteTransaction, walletName: String, categoryName: String?,
         categoryIcon: String?, categoryColor: String?) {
        serverId = r.id
        walletId = r.walletId ?? ""
        self.walletName = walletName
        categoryId = r.categoryId
        self.categoryName = categoryName
        self.categoryIcon = categoryIcon
        self.categoryColor = categoryColor
        type = r.type; amount = r.amount; note = r.note
        transactionDate = yyyyMMdd.date(from: r.transactionDate) ?? Date()
        updatedAt = r.updatedAt; syncStatus = "synced"
    }

    func update(from r: RemoteTransaction, walletName: String, categoryName: String?,
                categoryIcon: String?, categoryColor: String?) {
        walletId = r.walletId ?? ""
        self.walletName = walletName
        self.categoryName = categoryName
        self.categoryIcon = categoryIcon
        self.categoryColor = categoryColor
        type = r.type; amount = r.amount; note = r.note
        transactionDate = yyyyMMdd.date(from: r.transactionDate) ?? Date()
        updatedAt = r.updatedAt; syncStatus = "synced"
    }
}

@Model
final class LocalBudget {
    var serverId: String
    var categoryId: String
    var categoryName: String
    var categoryIcon: String?
    var categoryColor: String?
    var amount: Double
    var month: Date

    init(from r: RemoteBudget, categoryName: String, categoryIcon: String?, categoryColor: String?) {
        serverId = r.id
        categoryId = r.categoryId ?? ""
        self.categoryName = categoryName
        self.categoryIcon = categoryIcon
        self.categoryColor = categoryColor
        amount = r.amount
        month = yyyyMMdd.date(from: r.month) ?? Date()
    }

    func update(from r: RemoteBudget, categoryName: String, categoryIcon: String?, categoryColor: String?) {
        categoryId = r.categoryId ?? ""
        self.categoryName = categoryName
        self.categoryIcon = categoryIcon
        self.categoryColor = categoryColor
        amount = r.amount
        month = yyyyMMdd.date(from: r.month) ?? Date()
    }
}
