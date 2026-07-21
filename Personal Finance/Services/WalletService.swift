import Foundation
import SwiftData

@MainActor
final class WalletService {
    static let shared = WalletService()
    private let client = SupabaseService.shared.client
    private init() {}

    func create(
        name: String, type: String, initialBalance: Double,
        icon: String?, color: String?, isDefault: Bool,
        creditLimit: Double? = nil, statementDay: Int? = nil, paymentDueDay: Int? = nil,
        in ctx: ModelContext
    ) async throws {
        let userId = try await client.auth.session.user.id
        let remote: RemoteWallet
        if type == "credit" {
            struct CreditBody: Encodable {
                let user_id: String, name: String, type: String, balance: Double
                let icon: String?, color: String?, is_default: Bool
                let credit_limit: Double, statement_day: Int?, payment_due_day: Int?
            }
            let limit = creditLimit ?? 0
            remote = try await client
                .from("wallets")
                .insert(CreditBody(user_id: userId.uuidString, name: name, type: type,
                                   balance: limit, icon: icon, color: color, is_default: isDefault,
                                   credit_limit: limit, statement_day: statementDay,
                                   payment_due_day: paymentDueDay))
                .select().single().execute().value
        } else {
            struct Body: Encodable {
                let user_id: String, name: String, type: String, balance: Double
                let icon: String?, color: String?, is_default: Bool
            }
            remote = try await client
                .from("wallets")
                .insert(Body(user_id: userId.uuidString, name: name, type: type,
                             balance: initialBalance, icon: icon, color: color, is_default: isDefault))
                .select().single().execute().value
        }
        ctx.insert(LocalWallet(from: remote))
        try ctx.save()
    }

    func update(
        _ wallet: LocalWallet, name: String, type: String,
        icon: String?, color: String?, isDefault: Bool,
        creditLimit: Double? = nil, statementDay: Int? = nil, paymentDueDay: Int? = nil,
        in ctx: ModelContext
    ) async throws {
        let userId = try await client.auth.session.user.id
        let remote: RemoteWallet
        if type == "credit" {
            struct CreditBody: Encodable {
                let name: String, type: String, icon: String?, color: String?, is_default: Bool
                let credit_limit: Double, statement_day: Int?, payment_due_day: Int?, balance: Double
            }
            let newLimit = creditLimit ?? wallet.creditLimit ?? 0
            let debtUsed = max(0, (wallet.creditLimit ?? 0) - wallet.balance)
            let newBalance = newLimit - debtUsed
            remote = try await client
                .from("wallets")
                .update(CreditBody(name: name, type: type, icon: icon, color: color, is_default: isDefault,
                                   credit_limit: newLimit,
                                   statement_day: statementDay ?? wallet.statementDay,
                                   payment_due_day: paymentDueDay ?? wallet.paymentDueDay,
                                   balance: max(0, newBalance)))
                .eq("id", value: wallet.serverId)
                .eq("user_id", value: userId.uuidString)
                .select().single().execute().value
        } else {
            struct Body: Encodable {
                let name: String, type: String, icon: String?, color: String?, is_default: Bool
            }
            remote = try await client
                .from("wallets")
                .update(Body(name: name, type: type, icon: icon, color: color, is_default: isDefault))
                .eq("id", value: wallet.serverId)
                .eq("user_id", value: userId.uuidString)
                .select().single().execute().value
        }
        wallet.update(from: remote)
        try ctx.save()
    }

    func delete(_ wallet: LocalWallet, in ctx: ModelContext) async throws {
        let userId = try await client.auth.session.user.id
        if wallet.type != "credit", wallet.balance > 0 {
            let wallets = (try? ctx.fetch(FetchDescriptor<LocalWallet>())) ?? []
            guard let destination = wallets.first(where: {
                $0.serverId != wallet.serverId && $0.isDefault
            }) else {
                throw FinanceValidationError.missingDefaultWallet
            }
            try await TransferService.shared.transfer(
                from: wallet,
                to: destination,
                amount: wallet.balance,
                date: Date(),
                note: "Balance moved before deleting \(wallet.name)",
                in: ctx
            )
        }
        try await client.from("wallets").delete()
            .eq("id", value: wallet.serverId)
            .eq("user_id", value: userId.uuidString)
            .execute()
        ctx.delete(wallet)
        try ctx.save()
    }

    func payCredit(
        _ creditWallet: LocalWallet, from sourceWallet: LocalWallet,
        amount: Double, date: Date, note: String?,
        in ctx: ModelContext
    ) async throws {
        guard amount > 0 else { throw FinanceValidationError.invalidAmount }
        guard amount <= creditWallet.amountOwed else { throw FinanceValidationError.exceedsCreditDebt }
        guard sourceWallet.balance >= amount else { throw FinanceValidationError.insufficientFunds }

        try await TransferService.shared.transfer(
            from: sourceWallet, to: creditWallet,
            amount: amount, date: date, note: note, in: ctx
        )
    }
}
