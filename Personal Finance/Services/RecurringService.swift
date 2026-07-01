import Foundation
import SwiftData

@MainActor
final class RecurringService {
    static let shared = RecurringService()
    private let client = SupabaseService.shared.client
    private init() {}

    private let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        return f
    }()

    func create(
        type: String, amount: Double, frequency: String,
        startDate: Date, endDate: Date?,
        walletId: UUID?, categoryId: UUID?, note: String?,
        in ctx: ModelContext
    ) async throws {
        let userId = try await client.auth.session.user.id
        struct Body: Encodable {
            let user_id: String, type: String, amount: Double, frequency: String
            let start_date: String, end_date: String?, next_run_date: String
            let wallet_id: String?, category_id: String?, note: String?
        }
        let remote: RemoteRecurringTransaction = try await client
            .from("recurring_transactions")
            .insert(Body(
                user_id: userId.uuidString, type: type, amount: amount, frequency: frequency,
                start_date: df.string(from: startDate),
                end_date: endDate.map { df.string(from: $0) },
                next_run_date: df.string(from: startDate),
                wallet_id: walletId?.uuidString, category_id: categoryId?.uuidString,
                note: note?.isEmpty == true ? nil : note
            ))
            .select("*, categories(id, name, icon, color), wallets(id, name)")
            .single().execute().value
        ctx.insert(LocalRecurringTransaction(from: remote))
        try ctx.save()
    }

    func update(
        _ rec: LocalRecurringTransaction, amount: Double, frequency: String,
        endDate: Date?, walletId: UUID?, categoryId: UUID?, note: String?,
        in ctx: ModelContext
    ) async throws {
        struct Body: Encodable {
            let amount: Double, frequency: String, end_date: String?
            let wallet_id: String?, category_id: String?, note: String?
        }
        let remote: RemoteRecurringTransaction = try await client
            .from("recurring_transactions")
            .update(Body(amount: amount, frequency: frequency,
                        end_date: endDate.map { df.string(from: $0) },
                        wallet_id: walletId?.uuidString, category_id: categoryId?.uuidString,
                        note: note?.isEmpty == true ? nil : note))
            .eq("id", value: rec.serverId)
            .select("*, categories(id, name, icon, color), wallets(id, name)")
            .single().execute().value
        rec.update(from: remote)
        try ctx.save()
    }

    func delete(_ rec: LocalRecurringTransaction, in ctx: ModelContext) async throws {
        try await client.from("recurring_transactions").delete().eq("id", value: rec.serverId).execute()
        ctx.delete(rec)
        try ctx.save()
    }

    func processOverdue(transactions: [LocalRecurringTransaction], wallets: [LocalWallet], in ctx: ModelContext) async {
        let today = df.string(from: Date())
        let overdue = transactions.filter { rec in
            guard let nextRun = rec.nextRunDate else { return false }
            guard df.string(from: nextRun) <= today else { return false }
            if let end = rec.endDate, df.string(from: end) < today { return false }
            return true
        }
        guard !overdue.isEmpty else { return }

        for rec in overdue {
            guard let nextRun = rec.nextRunDate else { continue }
            let wallet = wallets.first { $0.serverId == rec.walletId }
            do {
                try await TransactionService.shared.create(
                    type: rec.type, amount: rec.amount, date: nextRun,
                    walletId: rec.walletId, categoryId: rec.categoryId,
                    note: rec.note, wallet: wallet, in: ctx
                )
                let newNextRun = nextRunDate(after: nextRun, frequency: rec.frequency)
                struct Body: Encodable { let next_run_date: String }
                let updated: RemoteRecurringTransaction = try await client
                    .from("recurring_transactions")
                    .update(Body(next_run_date: df.string(from: newNextRun)))
                    .eq("id", value: rec.serverId)
                    .select("*, categories(id, name, icon, color), wallets(id, name)")
                    .single().execute().value
                rec.update(from: updated)
            } catch {
                print("[RecurringService] error processing \(rec.serverId): \(error)")
            }
        }
        try? ctx.save()
    }
    private func nextRunDate(after date: Date, frequency: String) -> Date {
        let cal = Calendar.current
        switch frequency {
        case "daily":   return cal.date(byAdding: .day, value: 1, to: date)!
        case "weekly":  return cal.date(byAdding: .day, value: 7, to: date)!
        case "monthly": return cal.date(byAdding: .month, value: 1, to: date)!
        case "yearly":  return cal.date(byAdding: .year, value: 1, to: date)!
        default:        return cal.date(byAdding: .month, value: 1, to: date)!
        }
    }
}
