import Foundation
import SwiftData

@MainActor
final class TransferService {
    static let shared = TransferService()
    private let client = SupabaseService.shared.client
    private init() {}

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        return f
    }()

    func transfer(
        from fromWallet: LocalWallet,
        to toWallet: LocalWallet,
        amount: Double,
        date: Date,
        note: String?,
        in ctx: ModelContext
    ) async throws {
        guard amount > 0 else { throw FinanceValidationError.invalidAmount }
        guard fromWallet.serverId != toWallet.serverId else { throw FinanceValidationError.sameWallet }
        guard fromWallet.balance >= amount else { throw FinanceValidationError.insufficientFunds }

        let userId = try await client.auth.session.user.id
        let pairId = UUID()
        let dateStr = TransferService.df.string(from: date)
        let noteVal: String? = (note?.isEmpty == true) ? nil : note

        struct TxBody: Encodable {
            let user_id: String
            let wallet_id: String
            let type: String
            let amount: Double
            let transaction_date: String
            let note: String?
            let transfer_pair_id: String
        }

        let expense: RemoteTransaction = try await client
            .from("transactions")
            .insert(TxBody(
                user_id: userId.uuidString.lowercased(),
                wallet_id: fromWallet.serverId.uuidString.lowercased(),
                type: "expense",
                amount: amount,
                transaction_date: dateStr,
                note: noteVal,
                transfer_pair_id: pairId.uuidString.lowercased()
            ))
            .select("*, categories(id, name, icon, color), wallets(id, name)")
            .single()
            .execute()
            .value

        let income: RemoteTransaction = try await client
            .from("transactions")
            .insert(TxBody(
                user_id: userId.uuidString.lowercased(),
                wallet_id: toWallet.serverId.uuidString.lowercased(),
                type: "income",
                amount: amount,
                transaction_date: dateStr,
                note: noteVal,
                transfer_pair_id: pairId.uuidString.lowercased()
            ))
            .select("*, categories(id, name, icon, color), wallets(id, name)")
            .single()
            .execute()
            .value

        try await applyBalanceDelta(-amount, to: fromWallet)
        try await applyBalanceDelta(+amount, to: toWallet)

        ctx.insert(LocalTransaction(from: expense))
        ctx.insert(LocalTransaction(from: income))
        try ctx.save()
    }

    private func applyBalanceDelta(_ delta: Double, to wallet: LocalWallet) async throws {
        let newBalance = wallet.balance + delta
        struct B: Encodable { let balance: Double }
        try await client
            .from("wallets")
            .update(B(balance: newBalance))
            .eq("id", value: wallet.serverId)
            .execute()
        wallet.balance = newBalance
    }
}
