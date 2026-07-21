import Foundation
import Supabase

@MainActor
final class NotificationService {
    static let shared = NotificationService()
    private let client = SupabaseService.shared.client
    private init() {}

    private let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        return f
    }()

    // MARK: - Fetch

    func fetchNotifications() async throws -> [AppNotification] {
        let userId = try await client.auth.session.user.id

        let cal = Calendar.current
        let now = Date()
        let today = df.string(from: now)
        let monthComps = cal.dateComponents([.year, .month], from: now)
        let monthStart = df.string(from: cal.date(from: monthComps)!)
        let monthEnd   = df.string(from: cal.date(byAdding: .month, value: 1, to: cal.date(from: monthComps)!)!)
        let debtHorizon      = df.string(from: cal.date(byAdding: .day, value: 7,  to: now)!)
        let recurringHorizon = df.string(from: cal.date(byAdding: .day, value: 3,  to: now)!)
        let goalHorizon      = df.string(from: cal.date(byAdding: .day, value: 14, to: now)!)

        async let budgetsTask: [BRow]    = client.from("budgets")
            .select("id, amount, category_id, categories(name, icon)")
            .eq("user_id", value: userId).eq("month", value: monthStart)
            .execute().value
        async let txTask: [TRow]         = client.from("transactions")
            .select("category_id, amount")
            .eq("user_id", value: userId).eq("type", value: "expense")
            .gte("transaction_date", value: monthStart).lt("transaction_date", value: monthEnd)
            .execute().value
        async let debtsTask: [DRow]      = client.from("debts")
            .select("id, type, person_name, remaining_amount, due_date")
            .eq("user_id", value: userId).eq("status", value: "active")
            .execute().value
        async let recurringTask: [RRow]  = client.from("recurring_transactions")
            .select("id, type, amount, note, next_run_date, end_date, categories(name, icon)")
            .eq("user_id", value: userId)
            .lte("next_run_date", value: recurringHorizon)
            .execute().value
        async let goalsTask: [GRow]      = client.from("saving_goals")
            .select("id, name, icon, target_amount, current_amount, deadline")
            .eq("user_id", value: userId).eq("status", value: "active")
            .execute().value
        async let walletsTask: [WRow]    = client.from("wallets")
            .select("id, name, balance, credit_limit")
            .eq("user_id", value: userId).eq("type", value: "credit")
            .execute().value
        async let statesTask: [SRow]     = client.from("notification_states")
            .select("notification_id, read_at, dismissed_at")
            .eq("user_id", value: userId)
            .execute().value

        let (budgets, txs, debts, recurring, goals, wallets, states) =
            try await (budgetsTask, txTask, debtsTask, recurringTask, goalsTask, walletsTask, statesTask)

        return process(
            budgets: budgets, transactions: txs, debts: debts,
            recurring: recurring, goals: goals, wallets: wallets, states: states,
            userId: userId, today: today, monthEnd: monthEnd,
            debtHorizon: debtHorizon, recurringHorizon: recurringHorizon, goalHorizon: goalHorizon
        )
    }

    // MARK: - Generate + filter

    private func process(
        budgets: [BRow], transactions: [TRow], debts: [DRow],
        recurring: [RRow], goals: [GRow], wallets: [WRow], states: [SRow],
        userId: UUID, today: String, monthEnd: String,
        debtHorizon: String, recurringHorizon: String, goalHorizon: String
    ) -> [AppNotification] {
        var spending: [UUID: Double] = [:]
        for tx in transactions {
            if let id = tx.category_id { spending[id, default: 0] += tx.amount }
        }

        var notifs: [AppNotification] = []

        // Budget
        for b in budgets {
            let spent = b.category_id.map { spending[$0, default: 0] } ?? 0
            let name = b.categories?.name ?? "Budget"
            let icon = b.categories?.icon ?? "💰"
            if spent > b.amount {
                notifs.append(AppNotification(id: "budget_over:\(b.id)", type: "budget_over",
                    severity: .alert, title: "Budget exceeded",
                    message: "\(icon) \(name): \(fmt(spent)) / \(fmt(b.amount))",
                    destination: .budgets, isRead: false))
            } else if b.amount > 0, spent / b.amount >= 0.8 {
                notifs.append(AppNotification(id: "budget_near:\(b.id)", type: "budget_near",
                    severity: .warning, title: "Budget almost used",
                    message: "\(icon) \(name): \(Int(spent / b.amount * 100))% used",
                    destination: .budgets, isRead: false))
            }
        }

        // Debt
        for d in debts {
            guard d.remaining_amount > 0, let due = d.due_date else { continue }
            if due < today {
                notifs.append(AppNotification(id: "debt_overdue:\(d.id):\(due)", type: "debt_overdue",
                    severity: .alert, title: "Debt overdue",
                    message: "\(d.person_name) · \(fmt(d.remaining_amount))",
                    destination: .debts, isRead: false))
            } else if due <= debtHorizon {
                notifs.append(AppNotification(id: "debt_due:\(d.id):\(due)", type: "debt_due",
                    severity: .warning, title: "Debt due soon",
                    message: "\(d.person_name) · \(fmt(d.remaining_amount)) · due \(due)",
                    destination: .debts, isRead: false))
            }
        }

        // Recurring
        for r in recurring {
            guard let nextRun = r.next_run_date, nextRun <= recurringHorizon else { continue }
            if let end = r.end_date, end < nextRun { continue }
            let icon  = r.categories?.icon ?? "🔄"
            let label = (r.note?.isEmpty == false ? r.note : nil) ?? r.categories?.name ?? "Recurring"
            notifs.append(AppNotification(id: "recurring:\(r.id):\(nextRun)", type: "recurring_upcoming",
                severity: .info, title: "Upcoming recurring",
                message: "\(icon) \(label) · \(fmt(r.amount)) on \(nextRun)",
                destination: .recurring, isRead: false))
        }

        // Goals
        for g in goals {
            if g.target_amount > 0, g.current_amount >= g.target_amount {
                notifs.append(AppNotification(id: "goal_reached:\(g.id)", type: "goal_reached",
                    severity: .success, title: "Goal reached! 🎉",
                    message: "\(g.icon ?? "🎯") \(g.name)",
                    destination: .savingGoals, isRead: false))
                continue
            }
            if let deadline = g.deadline, deadline <= goalHorizon {
                let overdue = deadline < today
                notifs.append(AppNotification(
                    id: "goal_deadline:\(g.id):\(deadline):\(overdue ? "overdue" : "soon")",
                    type: "goal_deadline",
                    severity: overdue ? .alert : .warning,
                    title: overdue ? "Goal deadline passed" : "Goal deadline soon",
                    message: "\(g.icon ?? "🎯") \(g.name) · \(fmt(g.current_amount)) / \(fmt(g.target_amount))",
                    destination: .savingGoals, isRead: false))
            }
        }

        // Credit
        for w in wallets {
            guard let limit = w.credit_limit, limit > 0 else { continue }
            let used = limit - w.balance
            guard used / limit >= 0.8 else { continue }
            notifs.append(AppNotification(id: "credit:\(w.id)", type: "credit_high",
                severity: .warning, title: "Credit limit high",
                message: "\(w.name) · \(Int(used / limit * 100))% used",
                destination: .wallets, isRead: false))
        }

        // Apply states
        let stateById  = Dictionary(uniqueKeysWithValues: states.map { ($0.notification_id, $0) })
        let currentIds = Set(notifs.map { $0.id })

        // Fire-and-forget stale cleanup
        let staleIds = states.map { $0.notification_id }.filter { !currentIds.contains($0) }
        if !staleIds.isEmpty {
            Task {
                try? await client.from("notification_states")
                    .delete().eq("user_id", value: userId)
                    .in("notification_id", values: staleIds)
                    .execute()
            }
        }

        var visible = notifs
            .filter { stateById[$0.id]?.dismissed_at == nil }
            .map { n -> AppNotification in
                var copy = n
                copy.isRead = stateById[n.id]?.read_at != nil
                return copy
            }
        visible.sort {
            if $0.isRead != $1.isRead { return !$0.isRead }
            return $0.severity.rawValue < $1.severity.rawValue
        }
        return visible
    }

    // MARK: - Mark read / dismiss

    func markRead(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        let userId = try await client.auth.session.user.id
        let now = ISO8601DateFormatter().string(from: Date())
        struct Body: Encodable { let user_id, notification_id, read_at: String }
        try await client.from("notification_states")
            .upsert(ids.map { Body(user_id: userId.uuidString, notification_id: $0, read_at: now) },
                    onConflict: "user_id,notification_id")
            .execute()
    }

    func dismiss(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        let userId = try await client.auth.session.user.id
        let now = ISO8601DateFormatter().string(from: Date())
        struct Body: Encodable { let user_id, notification_id, dismissed_at: String }
        try await client.from("notification_states")
            .upsert(ids.map { Body(user_id: userId.uuidString, notification_id: $0, dismissed_at: now) },
                    onConflict: "user_id,notification_id")
            .execute()
    }

    // MARK: - Helpers

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "."
        f.maximumFractionDigits = 0
        return (f.string(from: NSNumber(value: v)) ?? "\(Int(v))") + " đ"
    }
}

// MARK: - Private Decodable row types

private struct CatInfo: Decodable { let name: String; let icon: String? }

private struct BRow: Decodable {
    let id: UUID; let amount: Double; let category_id: UUID?; let categories: CatInfo?
}
private struct TRow: Decodable { let category_id: UUID?; let amount: Double }
private struct DRow: Decodable {
    let id: UUID; let type: String; let person_name: String
    let remaining_amount: Double; let due_date: String?
}
private struct RRow: Decodable {
    let id: UUID; let type: String; let amount: Double
    let note: String?; let next_run_date: String?; let end_date: String?
    let categories: CatInfo?
}
private struct GRow: Decodable {
    let id: UUID; let name: String; let icon: String?
    let target_amount: Double; let current_amount: Double; let deadline: String?
}
private struct WRow: Decodable { let id: UUID; let name: String; let balance: Double; let credit_limit: Double? }
private struct SRow: Decodable { let notification_id: String; let read_at: String?; let dismissed_at: String? }
