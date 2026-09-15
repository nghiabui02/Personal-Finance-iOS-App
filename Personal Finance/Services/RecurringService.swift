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
        bankFee: Double = 0,
        in ctx: ModelContext
    ) async throws {
        let userId = try await client.auth.session.user.id
        struct Body: Encodable {
            let user_id: String, type: String, amount: Double, frequency: String
            let start_date: String, end_date: String?, next_run_date: String
            let wallet_id: String?, category_id: String?, note: String?
            let bank_fee: Double, active: Bool
        }
        let remote: RemoteRecurringTransaction = try await client
            .from("recurring_transactions")
            .insert(Body(
                user_id: userId.uuidString, type: type, amount: amount, frequency: frequency,
                start_date: df.string(from: startDate),
                end_date: endDate.map { df.string(from: $0) },
                next_run_date: df.string(from: startDate),
                wallet_id: walletId?.uuidString, category_id: categoryId?.uuidString,
                note: note?.isEmpty == true ? nil : note,
                bank_fee: bankFee, active: true
            ))
            .select("*, categories(id, name, icon, color), wallets(id, name)")
            .single().execute().value
        ctx.insert(LocalRecurringTransaction(from: remote))
        try ctx.save()
    }

    func update(
        _ rec: LocalRecurringTransaction, amount: Double, frequency: String,
        endDate: Date?, walletId: UUID?, categoryId: UUID?, note: String?,
        bankFee: Double,
        in ctx: ModelContext
    ) async throws {
        let userId = try await client.auth.session.user.id
        struct Body: Encodable {
            let amount: Double, frequency: String, end_date: String?
            let wallet_id: String?, category_id: String?, note: String?
            let bank_fee: Double
        }
        let remote: RemoteRecurringTransaction = try await client
            .from("recurring_transactions")
            .update(Body(amount: amount, frequency: frequency,
                        end_date: endDate.map { df.string(from: $0) },
                        wallet_id: walletId?.uuidString, category_id: categoryId?.uuidString,
                        note: note?.isEmpty == true ? nil : note,
                        bank_fee: bankFee))
            .eq("id", value: rec.serverId)
            .eq("user_id", value: userId.uuidString)
            .select("*, categories(id, name, icon, color), wallets(id, name)")
            .single().execute().value
        rec.update(from: remote)
        try ctx.save()
    }

    func toggleActive(_ rec: LocalRecurringTransaction, in ctx: ModelContext) async throws {
        let userId = try await client.auth.session.user.id
        let newActive = !rec.active
        let remote: RemoteRecurringTransaction
        if newActive, let nr = rec.nextRunDate {
            // Fast-forward past today so cron doesn't backfill missed periods
            let today = Calendar.current.startOfDay(for: Date())
            var candidate = nr
            while candidate <= today {
                candidate = nextRunDate(after: candidate, frequency: rec.frequency)
            }
            struct ResumeBody: Encodable { let active: Bool; let next_run_date: String }
            remote = try await client
                .from("recurring_transactions")
                .update(ResumeBody(active: true, next_run_date: df.string(from: candidate)))
                .eq("id", value: rec.serverId)
                .eq("user_id", value: userId.uuidString)
                .select("*, categories(id, name, icon, color), wallets(id, name)")
                .single().execute().value
        } else {
            struct PauseBody: Encodable { let active: Bool }
            remote = try await client
                .from("recurring_transactions")
                .update(PauseBody(active: newActive))
                .eq("id", value: rec.serverId)
                .eq("user_id", value: userId.uuidString)
                .select("*, categories(id, name, icon, color), wallets(id, name)")
                .single().execute().value
        }
        rec.update(from: remote)
        try ctx.save()
    }

    func skip(_ rec: LocalRecurringTransaction, in ctx: ModelContext) async throws {
        guard let nextRun = rec.nextRunDate else { return }
        let userId = try await client.auth.session.user.id
        let newNext = nextRunDate(after: nextRun, frequency: rec.frequency)
        struct Body: Encodable { let next_run_date: String }
        let remote: RemoteRecurringTransaction = try await client
            .from("recurring_transactions")
            .update(Body(next_run_date: df.string(from: newNext)))
            .eq("id", value: rec.serverId)
            .eq("user_id", value: userId.uuidString)
            .select("*, categories(id, name, icon, color), wallets(id, name)")
            .single().execute().value
        rec.update(from: remote)
        try ctx.save()
    }

    func delete(_ rec: LocalRecurringTransaction, in ctx: ModelContext) async throws {
        let userId = try await client.auth.session.user.id
        try await client.from("recurring_transactions").delete()
            .eq("id", value: rec.serverId)
            .eq("user_id", value: userId.uuidString)
            .execute()
        ctx.delete(rec)
        try ctx.save()
    }

    // Firing overdue recurring transactions is server-only: pg_cron job
    // `process-recurring-daily` runs for all users regardless of app opens.
    // A client-side equivalent would race the cron and double-create transactions.
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
