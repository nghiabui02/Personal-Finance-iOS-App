import Foundation
import SwiftData

@MainActor
final class DebtService {
    static let shared = DebtService()
    private let client = SupabaseService.shared.client
    private init() {}

    /// The debt row, its opening transaction and the wallet movement are written
    /// together — a wallet that cannot cover the loan no longer leaves a debt
    /// record behind with no money having moved.
    func create(
        type: String, personName: String, personContact: String?,
        amount: Double, walletId: UUID?, categoryId: UUID? = nil,
        dueDate: Date?, note: String?, date: Date = Date(),
        in ctx: ModelContext
    ) async throws {
        struct Params: Encodable {
            let p_type: String
            let p_person_name: String
            let p_amount: Double
            let p_date: String
            let p_person_contact: String?
            let p_due_date: String?
            let p_note: String?
            let p_wallet_id: String?
            let p_category_id: String?
        }
        do {
            let result: RPC.Envelope = try await client
                .rpc("create_debt", params: Params(
                    p_type: type,
                    p_person_name: personName,
                    p_amount: amount,
                    p_date: LedgerDate.string(from: date),
                    p_person_contact: personContact?.isEmpty == true ? nil : personContact,
                    p_due_date: dueDate.map { LedgerDate.string(from: $0) },
                    p_note: note?.isEmpty == true ? nil : note,
                    p_wallet_id: walletId?.uuidString,
                    p_category_id: categoryId?.uuidString
                ))
                .execute().value
            try RPCResultApplier.apply(result, in: ctx)
        } catch {
            throw error.asDisplayableError()
        }
    }

    /// Editing a debt's details touches no money, so it stays a plain update.
    func update(
        _ debt: LocalDebt, personName: String, personContact: String?,
        dueDate: Date?, note: String?, status: String? = nil, in ctx: ModelContext
    ) async throws {
        let userId = try await client.auth.session.user.id
        struct Body: Encodable {
            let person_name: String, person_contact: String?, due_date: String?, note: String?
            let status: String
        }
        let remote: RemoteDebt = try await client
            .from("debts")
            .update(Body(
                person_name: personName,
                person_contact: personContact?.isEmpty == true ? nil : personContact,
                due_date: dueDate.map { LedgerDate.string(from: $0) },
                note: note?.isEmpty == true ? nil : note,
                status: status ?? debt.status
            ))
            .eq("id", value: debt.serverId)
            .eq("user_id", value: userId.uuidString)
            .select().single().execute().value
        debt.update(from: remote)
        try ctx.save()
    }

    func delete(_ debt: LocalDebt, in ctx: ModelContext) async throws {
        let userId = try await client.auth.session.user.id
        try await client.from("debts").delete()
            .eq("id", value: debt.serverId)
            .eq("user_id", value: userId.uuidString)
            .execute()
        ctx.delete(debt)
        try ctx.save()
    }

    /// Collecting on a loan is income; repaying what you borrowed is an expense —
    /// the direction follows the debt, never the wallet it is settled from.
    func recordPayment(
        _ debt: LocalDebt, amount: Double, note: String?,
        date: Date = Date(), walletId: UUID?, categoryId: UUID? = nil,
        in ctx: ModelContext
    ) async throws {
        struct Params: Encodable {
            let p_debt_id: String
            let p_amount: Double
            let p_date: String
            let p_wallet_id: String?
            let p_category_id: String?
            let p_note: String?
        }
        do {
            let result: RPC.Envelope = try await client
                .rpc("record_debt_payment", params: Params(
                    p_debt_id: debt.serverId.uuidString,
                    p_amount: amount,
                    p_date: LedgerDate.string(from: date),
                    p_wallet_id: walletId?.uuidString,
                    p_category_id: categoryId?.uuidString,
                    p_note: note?.isEmpty == true ? nil : note
                ))
                .execute().value
            try RPCResultApplier.apply(result, in: ctx)
        } catch {
            throw error.asDisplayableError()
        }
    }

    /// Lending more / borrowing more: raises both the debt's total and what is
    /// still outstanding, and moves the wallet in the same breath.
    func addAmount(
        to debt: LocalDebt, amount: Double, note: String?,
        date: Date = Date(), walletId: UUID?, categoryId: UUID? = nil,
        in ctx: ModelContext
    ) async throws {
        struct Params: Encodable {
            let p_debt_id: String
            let p_amount: Double
            let p_date: String
            let p_wallet_id: String?
            let p_category_id: String?
            let p_note: String?
        }
        do {
            let result: RPC.Envelope = try await client
                .rpc("add_to_debt", params: Params(
                    p_debt_id: debt.serverId.uuidString,
                    p_amount: amount,
                    p_date: LedgerDate.string(from: date),
                    p_wallet_id: walletId?.uuidString,
                    p_category_id: categoryId?.uuidString,
                    p_note: note?.isEmpty == true ? nil : note
                ))
                .execute().value
            try RPCResultApplier.apply(result, in: ctx)
        } catch {
            throw error.asDisplayableError()
        }
    }
}
