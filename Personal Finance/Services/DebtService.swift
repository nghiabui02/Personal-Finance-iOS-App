import Foundation
import SwiftData

@MainActor
final class DebtService {
    static let shared = DebtService()
    private let client = SupabaseService.shared.client
    private init() {}

    private let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    func create(
        type: String, personName: String, personContact: String?,
        amount: Double, walletId: UUID?, dueDate: Date?, note: String?,
        wallet: LocalWallet?, in ctx: ModelContext
    ) async throws {
        let userId = try await client.auth.session.user.id
        struct Body: Encodable {
            let user_id: String, type: String, person_name: String
            let person_contact: String?, amount: Double, remaining_amount: Double
            let wallet_id: String?, due_date: String?, note: String?, status: String
        }
        let remote: RemoteDebt = try await client
            .from("debts")
            .insert(Body(
                user_id: userId.uuidString, type: type, person_name: personName,
                person_contact: personContact?.isEmpty == true ? nil : personContact,
                amount: amount, remaining_amount: amount,
                wallet_id: walletId?.uuidString,
                due_date: dueDate.map { df.string(from: $0) },
                note: note?.isEmpty == true ? nil : note,
                status: "active"
            ))
            .select().single().execute().value
        ctx.insert(LocalDebt(from: remote))

        if let wallet {
            let txType = type == "lend" ? "expense" : "income"
            try await TransactionService.shared.create(
                type: txType, amount: amount, date: Date(),
                walletId: walletId, categoryId: nil,
                note: "\(type == "lend" ? "Lend to" : "Borrow from") \(personName)",
                wallet: wallet, in: ctx
            )
        }
        try ctx.save()
    }

    func update(
        _ debt: LocalDebt, personName: String, personContact: String?,
        dueDate: Date?, note: String?, status: String? = nil, in ctx: ModelContext
    ) async throws {
        struct Body: Encodable {
            let person_name: String, person_contact: String?, due_date: String?, note: String?
            let status: String
        }
        let remote: RemoteDebt = try await client
            .from("debts")
            .update(Body(
                person_name: personName,
                person_contact: personContact?.isEmpty == true ? nil : personContact,
                due_date: dueDate.map { df.string(from: $0) },
                note: note?.isEmpty == true ? nil : note,
                status: status ?? debt.status
            ))
            .eq("id", value: debt.serverId)
            .select().single().execute().value
        debt.update(from: remote)
        try ctx.save()
    }

    func delete(_ debt: LocalDebt, in ctx: ModelContext) async throws {
        try await client.from("debts").delete().eq("id", value: debt.serverId).execute()
        ctx.delete(debt)
        try ctx.save()
    }

    func recordPayment(
        _ debt: LocalDebt, amount: Double, note: String?,
        date: Date = Date(), wallet: LocalWallet?, in ctx: ModelContext
    ) async throws {
        struct PayBody: Encodable {
            let debt_id: String, amount: Double, note: String?, type: String
        }
        try await client
            .from("debt_payments")
            .insert(PayBody(debt_id: debt.serverId.uuidString, amount: amount,
                            note: note?.isEmpty == true ? nil : note, type: "payment"))
            .execute()

        let newRemaining = max(0, debt.remainingAmount - amount)
        struct DebtBody: Encodable { let remaining_amount: Double, status: String }
        let newStatus = newRemaining == 0 ? "completed" : debt.status
        let remote: RemoteDebt = try await client
            .from("debts")
            .update(DebtBody(remaining_amount: newRemaining, status: newStatus))
            .eq("id", value: debt.serverId)
            .select().single().execute().value
        debt.update(from: remote)

        if let wallet {
            let txType = debt.type == "lend" ? "income" : "expense"
            try await TransactionService.shared.create(
                type: txType, amount: amount, date: date,
                walletId: wallet.serverId, categoryId: nil,
                note: "Payment: \(debt.personName)",
                wallet: wallet, in: ctx
            )
        }
        try ctx.save()
    }

    func addAmount(
        to debt: LocalDebt, amount: Double, note: String?,
        date: Date = Date(), wallet: LocalWallet?,
        in ctx: ModelContext
    ) async throws {
        struct PayBody: Encodable {
            let debt_id: String, amount: Double, note: String?, type: String
        }
        try await client
            .from("debt_payments")
            .insert(PayBody(debt_id: debt.serverId.uuidString, amount: amount,
                            note: note?.isEmpty == true ? nil : note, type: "addition"))
            .execute()

        let newAmount = debt.amount + amount
        let newRemaining = debt.remainingAmount + amount
        struct DebtBody: Encodable { let amount: Double, remaining_amount: Double, status: String }
        let remote: RemoteDebt = try await client
            .from("debts")
            .update(DebtBody(amount: newAmount, remaining_amount: newRemaining, status: "active"))
            .eq("id", value: debt.serverId)
            .select().single().execute().value
        debt.update(from: remote)

        if let wallet {
            let txType = debt.type == "lend" ? "expense" : "income"
            try await TransactionService.shared.create(
                type: txType, amount: amount, date: date,
                walletId: wallet.serverId, categoryId: nil,
                note: "Addition: \(debt.personName)",
                wallet: wallet, in: ctx
            )
        }
        try ctx.save()
    }
}
