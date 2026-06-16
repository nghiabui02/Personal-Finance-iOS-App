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

@Model
final class LocalDebt {
    var serverId: UUID
    var walletId: UUID?
    var type: String
    var personName: String
    var personContact: String?
    var amount: Double
    var remainingAmount: Double
    var dueDate: Date?
    var status: String
    var note: String?
    var updatedAt: Date

    init(from r: RemoteDebt) {
        serverId = r.id; walletId = r.walletId; type = r.type
        personName = r.personName; personContact = r.personContact
        amount = r.amount; remainingAmount = r.remainingAmount
        dueDate = r.dueDate.flatMap { yyyyMMdd.date(from: $0) }
        status = r.status; note = r.note; updatedAt = r.updatedAt
    }
    func update(from r: RemoteDebt) {
        walletId = r.walletId; type = r.type
        personName = r.personName; personContact = r.personContact
        amount = r.amount; remainingAmount = r.remainingAmount
        dueDate = r.dueDate.flatMap { yyyyMMdd.date(from: $0) }
        status = r.status; note = r.note; updatedAt = r.updatedAt
    }
}

@Model
final class LocalSavingGoal {
    var serverId: UUID
    var name: String
    var icon: String?
    var targetAmount: Double
    var currentAmount: Double
    var deadline: Date?
    var status: String
    var note: String?
    var updatedAt: Date

    var progress: Double { targetAmount > 0 ? min(currentAmount / targetAmount, 1.0) : 0 }

    init(from r: RemoteSavingGoal) {
        serverId = r.id; name = r.name; icon = r.icon
        targetAmount = r.targetAmount; currentAmount = r.currentAmount
        deadline = r.deadline.flatMap { yyyyMMdd.date(from: $0) }
        status = r.status; note = r.note; updatedAt = r.updatedAt
    }
    func update(from r: RemoteSavingGoal) {
        name = r.name; icon = r.icon
        targetAmount = r.targetAmount; currentAmount = r.currentAmount
        deadline = r.deadline.flatMap { yyyyMMdd.date(from: $0) }
        status = r.status; note = r.note; updatedAt = r.updatedAt
    }
}

@Model
final class LocalRecurringTransaction {
    var serverId: UUID
    var walletId: UUID?
    var walletName: String?
    var categoryId: UUID?
    var categoryName: String?
    var categoryIcon: String?
    var categoryColor: String?
    var type: String
    var amount: Double
    var note: String?
    var frequency: String
    var startDate: Date
    var endDate: Date?
    var nextRunDate: Date?
    var updatedAt: Date

    init(from r: RemoteRecurringTransaction) {
        serverId = r.id; walletId = r.walletId; walletName = r.wallets?.name
        categoryId = r.categoryId; categoryName = r.categories?.name
        categoryIcon = r.categories?.icon; categoryColor = r.categories?.color
        type = r.type; amount = r.amount; note = r.note; frequency = r.frequency
        startDate = yyyyMMdd.date(from: r.startDate) ?? Date()
        endDate = r.endDate.flatMap { yyyyMMdd.date(from: $0) }
        nextRunDate = r.nextRunDate.flatMap { yyyyMMdd.date(from: $0) }
        updatedAt = r.updatedAt
    }
    func update(from r: RemoteRecurringTransaction) {
        walletId = r.walletId; walletName = r.wallets?.name
        categoryId = r.categoryId; categoryName = r.categories?.name
        categoryIcon = r.categories?.icon; categoryColor = r.categories?.color
        type = r.type; amount = r.amount; note = r.note; frequency = r.frequency
        startDate = yyyyMMdd.date(from: r.startDate) ?? Date()
        endDate = r.endDate.flatMap { yyyyMMdd.date(from: $0) }
        nextRunDate = r.nextRunDate.flatMap { yyyyMMdd.date(from: $0) }
        updatedAt = r.updatedAt
    }
}
