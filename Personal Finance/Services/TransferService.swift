import Foundation
import SwiftData

@MainActor
final class TransferService {
    static let shared = TransferService()
    private let client = SupabaseService.shared.client
    private init() {}

    /// Both wallets are locked in id order inside the database function — two
    /// transfers running in opposite directions between the same pair would
    /// otherwise deadlock, and the balance check could pass twice.
    func transfer(
        from fromWallet: LocalWallet,
        to toWallet: LocalWallet,
        amount: Double,
        date: Date,
        note: String?,
        in ctx: ModelContext
    ) async throws {
        struct Params: Encodable {
            let p_from_wallet_id: String
            let p_to_wallet_id: String
            let p_amount: Double
            let p_date: String
            let p_note: String?
        }
        do {
            let result: RPC.Envelope = try await client
                .rpc("transfer_funds", params: Params(
                    p_from_wallet_id: fromWallet.serverId.uuidString,
                    p_to_wallet_id: toWallet.serverId.uuidString,
                    p_amount: amount,
                    p_date: LedgerDate.string(from: date),
                    p_note: note?.isEmpty == true ? nil : note
                ))
                .execute().value
            try RPCResultApplier.apply(result, in: ctx)
        } catch {
            throw error.asDisplayableError()
        }
    }
}
