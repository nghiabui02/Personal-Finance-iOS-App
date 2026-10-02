import Foundation
import SwiftData

/// Every method here is one `rpc` call.
///
/// The database functions run as a single transaction, lock the wallets they
/// touch, and raise on any rule they enforce — so there is no window where a row
/// exists without its balance change, and two concurrent spends can no longer
/// both read "enough funds" and both go through.
@MainActor
final class TransactionService {
    static let shared = TransactionService()
    private let client = SupabaseService.shared.client
    private init() {}

    func create(
        type: String, amount: Double, date: Date,
        walletId: UUID?, categoryId: UUID?, note: String?,
        bankFee: Double = 0,
        in ctx: ModelContext
    ) async throws {
        struct Params: Encodable {
            let p_type: String
            let p_amount: Double
            let p_transaction_date: String
            let p_category_id: String?
            let p_wallet_id: String?
            let p_note: String?
            let p_bank_fee: Double?
        }
        do {
            let result: RPC.Envelope = try await client
                .rpc("create_transaction", params: Params(
                    p_type: type,
                    p_amount: amount,
                    p_transaction_date: LedgerDate.string(from: date),
                    p_category_id: categoryId?.uuidString,
                    p_wallet_id: walletId?.uuidString,
                    p_note: note?.isEmpty == true ? nil : note,
                    p_bank_fee: bankFee > 0 ? bankFee : nil
                ))
                .execute().value
            try RPCResultApplier.apply(result, in: ctx)
        } catch {
            throw error.asDisplayableError()
        }
    }

    func update(
        _ tx: LocalTransaction,
        type: String, amount: Double, date: Date,
        walletId: UUID?, categoryId: UUID?, note: String?,
        bankFee: Double = 0,
        in ctx: ModelContext
    ) async throws {
        struct Params: Encodable {
            let p_id: String
            let p_type: String
            let p_amount: Double
            let p_transaction_date: String
            let p_category_id: String?
            let p_wallet_id: String?
            let p_note: String?
            let p_bank_fee: Double?
        }
        do {
            let result: RPC.Envelope = try await client
                .rpc("update_transaction", params: Params(
                    p_id: tx.serverId.uuidString,
                    p_type: type,
                    p_amount: amount,
                    p_transaction_date: LedgerDate.string(from: date),
                    p_category_id: categoryId?.uuidString,
                    p_wallet_id: walletId?.uuidString,
                    p_note: note?.isEmpty == true ? nil : note,
                    p_bank_fee: bankFee > 0 ? bankFee : nil
                ))
                .execute().value
            try RPCResultApplier.apply(result, in: ctx)
        } catch {
            throw error.asDisplayableError()
        }
    }

    /// Deleting one leg of a transfer removes both legs and restores both wallets —
    /// the server decides what that means, so a transfer can no longer be left
    /// half-deleted with the other wallet permanently wrong.
    func delete(_ tx: LocalTransaction, in ctx: ModelContext) async throws {
        struct Params: Encodable { let p_id: String }
        do {
            let result: RPC.Envelope = try await client
                .rpc("delete_transaction", params: Params(p_id: tx.serverId.uuidString))
                .execute().value
            try RPCResultApplier.apply(result, in: ctx)
        } catch {
            throw error.asDisplayableError()
        }
    }
}
