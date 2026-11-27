import Foundation
import SwiftData

@MainActor
final class DebtService {
    static let shared = DebtService()
    private init() {}

    /// The debt row, its opening transaction and the wallet movement are written
    /// together — a wallet that cannot cover the loan no longer leaves a debt
    /// record behind with no money having moved.
    func create(
        type: DebtKind, personName: String, personContact: String?,
        amount: Decimal, walletId: UUID?, categoryId: UUID? = nil,
        dueDate: Date?, note: String?, date: Date = Date(),
        in ctx: ModelContext
    ) async throws {
        struct Params: Encodable {
            let p_type: DebtKind
            let p_person_name: String
            let p_amount: Decimal
            let p_date: String
            let p_person_contact: String?
            let p_due_date: String?
            let p_note: String?
            let p_wallet_id: String?
            let p_user_category_id: String?
        }
        try await RPCResultApplier.perform("create_debt", in: ctx) { _ in
            Params(
                p_type: type,
                p_person_name: personName,
                p_amount: amount,
                p_date: LedgerDate.string(from: date),
                p_person_contact: personContact?.isEmpty == true ? nil : personContact,
                p_due_date: dueDate.map { LedgerDate.string(from: $0) },
                p_note: note?.isEmpty == true ? nil : note,
                p_wallet_id: walletId?.uuidString,
                p_user_category_id: categoryId?.uuidString
            )
        }
    }

    /// Editing a debt's details touches no money, so it stays a plain update.
    func update(
        _ debt: LocalDebt, personName: String, personContact: String?,
        dueDate: Date?, note: String?, status: DebtStatus? = nil, in ctx: ModelContext
    ) async throws {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let client = mutation.client
        let remote: RemoteDebt = try await client
            .from("debts")
            .update(DebtUpdate(
                person_name: personName,
                person_contact: personContact?.isEmpty == true ? nil : personContact,
                due_date: dueDate.map { LedgerDate.string(from: $0) },
                note: note?.isEmpty == true ? nil : note,
                status: status ?? debt.status
            ))
            .eq("id", value: debt.serverId)
            .eq("user_id", value: mutation.userId.uuidString)
            .select().single().execute().value
        try LocalDataStore.validate(mutation.session)
        debt.update(from: remote)
        try LocalDataStore.saveMutation(in: ctx)
    }

    func delete(_ debt: LocalDebt, in ctx: ModelContext) async throws {
        let mutation = try await LocalDataStore.beginMutation()
        defer { LocalDataStore.endMutation(mutation.session) }
        let client = mutation.client
        try await client.from("debts").delete()
            .eq("id", value: debt.serverId)
            .eq("user_id", value: mutation.userId.uuidString)
            .execute()
        try LocalDataStore.validate(mutation.session)
        ctx.delete(debt)
        try LocalDataStore.saveMutation(in: ctx)
    }

    /// Collecting on a loan is income; repaying what you borrowed is an expense —
    /// the direction follows the debt, never the wallet it is settled from.
    func recordPayment(
        _ debt: LocalDebt, amount: Decimal, note: String?,
        date: Date = Date(), walletId: UUID?, categoryId: UUID? = nil,
        in ctx: ModelContext
    ) async throws {
        struct Params: Encodable {
            let p_debt_id: String
            let p_amount: Decimal
            let p_date: String
            let p_wallet_id: String?
            let p_user_category_id: String?
            let p_note: String?
        }
        try await RPCResultApplier.perform("record_debt_payment", in: ctx) { _ in
            Params(
                p_debt_id: debt.serverId.uuidString,
                p_amount: amount,
                p_date: LedgerDate.string(from: date),
                p_wallet_id: walletId?.uuidString,
                p_user_category_id: categoryId?.uuidString,
                p_note: note?.isEmpty == true ? nil : note
            )
        }
    }

    /// Lending more / borrowing more: raises both the debt's total and what is
    /// still outstanding, and moves the wallet in the same breath.
    func addAmount(
        to debt: LocalDebt, amount: Decimal, note: String?,
        date: Date = Date(), walletId: UUID?, categoryId: UUID? = nil,
        in ctx: ModelContext
    ) async throws {
        struct Params: Encodable {
            let p_debt_id: String
            let p_amount: Decimal
            let p_date: String
            let p_wallet_id: String?
            let p_user_category_id: String?
            let p_note: String?
        }
        try await RPCResultApplier.perform("add_to_debt", in: ctx) { _ in
            Params(
                p_debt_id: debt.serverId.uuidString,
                p_amount: amount,
                p_date: LedgerDate.string(from: date),
                p_wallet_id: walletId?.uuidString,
                p_user_category_id: categoryId?.uuidString,
                p_note: note?.isEmpty == true ? nil : note
            )
        }
    }
}

/// The editable details of a debt. A cleared field must reach the server as an explicit
/// `null`; synthesized encoding would drop the key and keep the old value.
struct DebtUpdate: Encodable {
    let person_name: String
    let person_contact: String?
    let due_date: String?
    let note: String?
    let status: DebtStatus

    private enum CodingKeys: String, CodingKey {
        case person_name, person_contact, due_date, note, status
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(person_name, forKey: .person_name)
        try container.encode(person_contact, forKey: .person_contact)
        try container.encode(due_date, forKey: .due_date)
        try container.encode(note, forKey: .note)
        try container.encode(status, forKey: .status)
    }
}
