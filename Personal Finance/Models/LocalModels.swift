import Foundation
import SwiftData

// Kind columns are stored as their raw text (`typeRaw`, `statusRaw`, ...) and read
// through a typed property: the text keeps the store independent of how SwiftData
// would encode an enum, and the typed property is what the rest of the app touches.
// `originalName` points each raw column at the name older builds stored it under
// (`type`, `status`, `frequency`), so an upgrade migrates the offline cache in place
// instead of failing and wiping it.

@Model
final class LocalWallet {
    var serverId: UUID
    var name: String
    @Attribute(originalName: "type") private var typeRaw: String
    var balance: Decimal
    var isDefault: Bool
    var color: String?
    var icon: String?
    var updatedAt: Date
    var creditLimit: Decimal?
    var statementDay: Int?
    var paymentDueDay: Int?

    var type: WalletKind {
        get { WalletKind(wireValue: typeRaw) }
        set { typeRaw = newValue.rawValue }
    }

    init(from r: RemoteWallet) {
        serverId = r.id; name = r.name; typeRaw = r.type.rawValue
        balance = r.balance; isDefault = r.isDefault
        color = r.color; icon = r.icon; updatedAt = r.updatedAt
        creditLimit = r.creditLimit; statementDay = r.statementDay
        paymentDueDay = r.paymentDueDay
    }
    func update(from r: RemoteWallet) {
        setIfChanged(\.name, r.name); setIfChanged(\.type, r.type); setIfChanged(\.balance, r.balance)
        setIfChanged(\.isDefault, r.isDefault); setIfChanged(\.color, r.color); setIfChanged(\.icon, r.icon)
        setIfChanged(\.updatedAt, r.updatedAt)
        setIfChanged(\.creditLimit, r.creditLimit); setIfChanged(\.statementDay, r.statementDay)
        setIfChanged(\.paymentDueDay, r.paymentDueDay)
    }

    var amountOwed: Decimal {
        guard type == .credit else { return 0 }
        return max(0, (creditLimit ?? 0) - balance)
    }

    var displayIcon: String {
        if let icon, !icon.isEmpty { return icon }
        switch type {
        case .cash: return "💵"
        case .bank: return "🏦"
        case .eWallet: return "📱"
        case .investment: return "📈"
        case .credit: return "💳"
        case .other: return "💼"
        }
    }

    @MainActor var typeLabel: String {
        switch type {
        case .cash: return AppLocalization.shared.language.text("Cash")
        case .bank: return AppLocalization.shared.language.text("Bank")
        case .eWallet: return AppLocalization.shared.language.text("E-Wallet")
        case .investment: return AppLocalization.shared.language.text("Investment")
        case .credit: return AppLocalization.shared.language.text("Credit")
        case .other: return AppLocalization.shared.language.text("Other")
        }
    }
}

@Model
final class LocalCategory {
    var serverId: UUID
    var name: String
    @Attribute(originalName: "type") private var typeRaw: String
    var icon: String?
    var color: String?
    var isDefault: Bool = false
    var systemKey: String?

    var type: TransactionKind {
        get { TransactionKind(wireValue: typeRaw) }
        set { typeRaw = newValue.rawValue }
    }

    init(from r: RemoteCategory) {
        serverId = r.id; name = r.displayName; typeRaw = r.type.rawValue
        icon = r.icon; color = r.color; isDefault = r.isDefault
        systemKey = r.systemKey
    }
    func update(from r: RemoteCategory) {
        setIfChanged(\.name, r.displayName); setIfChanged(\.type, r.type); setIfChanged(\.icon, r.icon)
        setIfChanged(\.color, r.color); setIfChanged(\.isDefault, r.isDefault)
        setIfChanged(\.systemKey, r.systemKey)
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
    @Attribute(originalName: "type") private var typeRaw: String
    var amount: Decimal
    var note: String?
    var transactionDate: Date
    var updatedAt: Date
    var syncStatus: String
    var transferPairId: UUID?
    var debtPaymentId: UUID?
    var bankFee: Decimal?

    var type: TransactionKind {
        get { TransactionKind(wireValue: typeRaw) }
        set { typeRaw = newValue.rawValue }
    }

    var isTransfer: Bool { transferPairId != nil }

    /// `amount` with the sign it has on a balance: income adds, expense subtracts.
    var signedAmount: Decimal { type == .income ? amount : -amount }

    init(from r: RemoteTransaction) {
        serverId = r.id
        walletId = r.walletId
        walletName = r.wallets?.name ?? "Unknown Wallet"
        categoryId = r.categoryId
        categoryName = r.categories?.displayName
        categoryIcon = r.categories?.icon
        categoryColor = r.categories?.color
        typeRaw = r.type.rawValue; amount = r.amount; note = r.note
        transactionDate = r.transactionDate.date
        updatedAt = r.updatedAt; syncStatus = "synced"
        transferPairId = r.transferPairId
        debtPaymentId = r.debtPaymentId
        bankFee = r.bankFee
    }

    func update(from r: RemoteTransaction) {
        setIfChanged(\.walletId, r.walletId)
        setIfChanged(\.walletName, r.wallets?.name ?? "Unknown Wallet")
        setIfChanged(\.categoryId, r.categoryId)
        setIfChanged(\.categoryName, r.categories?.displayName)
        setIfChanged(\.categoryIcon, r.categories?.icon)
        setIfChanged(\.categoryColor, r.categories?.color)
        setIfChanged(\.type, r.type); setIfChanged(\.amount, r.amount); setIfChanged(\.note, r.note)
        setIfChanged(\.transactionDate, r.transactionDate.date)
        setIfChanged(\.updatedAt, r.updatedAt); setIfChanged(\.syncStatus, "synced")
        setIfChanged(\.transferPairId, r.transferPairId)
        setIfChanged(\.debtPaymentId, r.debtPaymentId)
        setIfChanged(\.bankFee, r.bankFee)
    }
}

@Model
final class LocalBudget {
    var serverId: UUID
    var categoryId: UUID?
    var categoryName: String
    var categoryIcon: String?
    var categoryColor: String?
    var amount: Decimal
    var month: Date
    var rollover: Bool = false
    var active: Bool = true

    init(from r: RemoteBudget) {
        serverId = r.id
        categoryId = r.categoryId
        categoryName = r.categories?.displayName ?? "Unknown"
        categoryIcon = r.categories?.icon
        categoryColor = r.categories?.color
        amount = r.amount
        month = r.month.date
        rollover = r.rollover
        active = r.active
    }

    func update(from r: RemoteBudget) {
        setIfChanged(\.categoryId, r.categoryId)
        setIfChanged(\.categoryName, r.categories?.displayName ?? "Unknown")
        setIfChanged(\.categoryIcon, r.categories?.icon)
        setIfChanged(\.categoryColor, r.categories?.color)
        setIfChanged(\.amount, r.amount)
        setIfChanged(\.month, r.month.date)
        setIfChanged(\.rollover, r.rollover)
        setIfChanged(\.active, r.active)
    }
}

@Model
final class LocalDebt {
    var serverId: UUID
    var walletId: UUID?
    @Attribute(originalName: "type") private var typeRaw: String
    var personName: String
    var personContact: String?
    var amount: Decimal
    var remainingAmount: Decimal
    var dueDate: Date?
    @Attribute(originalName: "status") private var statusRaw: String
    var note: String?
    var updatedAt: Date

    var type: DebtKind {
        get { DebtKind(wireValue: typeRaw) }
        set { typeRaw = newValue.rawValue }
    }

    var status: DebtStatus {
        get { DebtStatus(wireValue: statusRaw) }
        set { statusRaw = newValue.rawValue }
    }

    init(from r: RemoteDebt) {
        serverId = r.id; walletId = r.walletId; typeRaw = r.type.rawValue
        personName = r.personName; personContact = r.personContact
        amount = r.amount; remainingAmount = r.remainingAmount
        dueDate = r.dueDate?.date
        statusRaw = r.status.rawValue; note = r.note; updatedAt = r.updatedAt
    }
    func update(from r: RemoteDebt) {
        setIfChanged(\.walletId, r.walletId); setIfChanged(\.type, r.type)
        setIfChanged(\.personName, r.personName); setIfChanged(\.personContact, r.personContact)
        setIfChanged(\.amount, r.amount); setIfChanged(\.remainingAmount, r.remainingAmount)
        setIfChanged(\.dueDate, r.dueDate?.date)
        setIfChanged(\.status, r.status); setIfChanged(\.note, r.note); setIfChanged(\.updatedAt, r.updatedAt)
    }
}

@Model
final class LocalSavingGoal {
    var serverId: UUID
    var name: String
    var icon: String?
    var targetAmount: Decimal
    var currentAmount: Decimal
    var deadline: Date?
    @Attribute(originalName: "status") private var statusRaw: String
    var note: String?
    var updatedAt: Date

    var status: GoalStatus {
        get { GoalStatus(wireValue: statusRaw) }
        set { statusRaw = newValue.rawValue }
    }

    /// Share of the target reached, capped at 1 — a ratio for progress bars, not money.
    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min((currentAmount / targetAmount).doubleValue, 1.0)
    }

    init(from r: RemoteSavingGoal) {
        serverId = r.id; name = r.name; icon = r.icon
        targetAmount = r.targetAmount; currentAmount = r.currentAmount
        deadline = r.deadline?.date
        statusRaw = r.status.rawValue; note = r.note; updatedAt = r.updatedAt
    }
    func update(from r: RemoteSavingGoal) {
        setIfChanged(\.name, r.name); setIfChanged(\.icon, r.icon)
        setIfChanged(\.targetAmount, r.targetAmount); setIfChanged(\.currentAmount, r.currentAmount)
        setIfChanged(\.deadline, r.deadline?.date)
        setIfChanged(\.status, r.status); setIfChanged(\.note, r.note); setIfChanged(\.updatedAt, r.updatedAt)
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
    @Attribute(originalName: "type") private var typeRaw: String
    var amount: Decimal
    var note: String?
    @Attribute(originalName: "frequency") private var frequencyRaw: String
    var startDate: Date
    var endDate: Date?
    var nextRunDate: Date?
    var updatedAt: Date
    var active: Bool = true
    var bankFee: Decimal = 0

    var type: TransactionKind {
        get { TransactionKind(wireValue: typeRaw) }
        set { typeRaw = newValue.rawValue }
    }

    var frequency: RecurringFrequency {
        get { RecurringFrequency(wireValue: frequencyRaw) }
        set { frequencyRaw = newValue.rawValue }
    }

    init(from r: RemoteRecurringTransaction) {
        serverId = r.id; walletId = r.walletId; walletName = r.wallets?.name
        categoryId = r.categoryId; categoryName = r.categories?.displayName
        categoryIcon = r.categories?.icon; categoryColor = r.categories?.color
        typeRaw = r.type.rawValue; amount = r.amount; note = r.note; frequencyRaw = r.frequency.rawValue
        startDate = r.startDate.date
        endDate = r.endDate?.date
        nextRunDate = r.nextRunDate?.date
        updatedAt = r.updatedAt
        active = r.active
        bankFee = r.bankFee ?? 0
    }
    func update(from r: RemoteRecurringTransaction) {
        setIfChanged(\.walletId, r.walletId); setIfChanged(\.walletName, r.wallets?.name)
        setIfChanged(\.categoryId, r.categoryId); setIfChanged(\.categoryName, r.categories?.displayName)
        setIfChanged(\.categoryIcon, r.categories?.icon); setIfChanged(\.categoryColor, r.categories?.color)
        setIfChanged(\.type, r.type); setIfChanged(\.amount, r.amount); setIfChanged(\.note, r.note)
        setIfChanged(\.frequency, r.frequency)
        setIfChanged(\.startDate, r.startDate.date)
        setIfChanged(\.endDate, r.endDate?.date)
        setIfChanged(\.nextRunDate, r.nextRunDate?.date)
        setIfChanged(\.updatedAt, r.updatedAt)
        setIfChanged(\.active, r.active)
        setIfChanged(\.bankFee, r.bankFee ?? 0)
    }
}
