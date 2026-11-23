import Foundation
import Supabase

@MainActor
final class NotificationService {
    static let shared = NotificationService()
    private let client = SupabaseService.shared.client
    private init() {}

    // MARK: - Fetch

    func fetchNotifications() async throws -> [AppNotification] {
        guard let session = LocalDataStore.session else { throw CancellationError() }
        let dataClient = try await LocalDataStore.authenticatedClient(for: session)
        let userId = session.userId
        let today = LedgerDate.string(from: Date())
        let calendar = LedgerDate.calendar
        let now = Date()
        guard let month = LedgerDate.startOfMonth(for: now),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: month) else { return [] }
        let monthStart = LedgerDate.string(from: month)
        let monthEnd = LedgerDate.string(from: nextMonth)
        let debtHorizon = LedgerDate.string(from: calendar.date(byAdding: .day, value: 7, to: now) ?? now)
        let recurringHorizon = LedgerDate.string(from: calendar.date(byAdding: .day, value: 3, to: now) ?? now)
        let goalHorizon = LedgerDate.string(from: calendar.date(byAdding: .day, value: 14, to: now) ?? now)

        async let budgetsTask: [RemoteBudget] = dataClient.readOwnedRows(
            "budgets", columns: CategoryProjection.withCategory, userId: userId)
        async let debtsTask: [RemoteDebt] = dataClient.readOwnedRows("debts", userId: userId)
        async let recurringTask: [RemoteRecurringTransaction] = dataClient.readOwnedRows(
            "recurring_transactions", columns: CategoryProjection.withCategory, userId: userId)
        async let goalsTask: [RemoteSavingGoal] = dataClient.readOwnedRows("saving_goals", userId: userId)
        async let walletsTask: [RemoteWallet] = dataClient.readOwnedRows("wallets", userId: userId)
        async let statesTask: [NotificationState] = dataClient.readOwnedRows(
            "notification_states", columns: "notification_id,read_at,dismissed_at", userId: userId,
            idColumn: "notification_id"
        )

        let budgets = try await budgetsTask
        let currentBudgets = budgets.filter { $0.active && $0.month == monthStart }
        let spending = currentBudgets.isEmpty ? [:] : try await budgetSpending(
            from: budgets.map(\.month).min() ?? monthStart, to: monthEnd, using: dataClient
        )
        let usage = BudgetUsageCalculator.calculate(budgets: budgets, spending: spending)
        let (debts, recurring, goals, wallets, states) = try await (
            debtsTask, recurringTask, goalsTask, walletsTask, statesTask
        )
        try LocalDataStore.validate(session)

        return process(
            budgets: currentBudgets, usage: usage, debts: debts.filter { $0.status == "active" },
            recurring: recurring.filter(\.active), goals: goals.filter { $0.status == "active" },
            wallets: wallets.filter { $0.type == "credit" }, states: states,
            client: dataClient, session: session, today: today, debtHorizon: debtHorizon,
            recurringHorizon: recurringHorizon, goalHorizon: goalHorizon
        )
    }

    private func budgetSpending(
        from start: String, to end: String, using client: PostgrestClient
    ) async throws -> BudgetUsageCalculator.MonthlySpending {
        struct Total: Decodable {
            let date: String
            let type: String
            let amount: Double
            let categoryId: UUID?
            let categories: CategoryReference?

            enum CodingKeys: String, CodingKey {
                case type, amount, categories
                case date = "transaction_date"
                case categoryId = "user_category_id"
            }
        }
        let params: [String: AnyJSON] = ["p_start": .string(start), "p_end": .string(end), "p_monthly": true]
        let totals: [Total] = try await client.rpc("report_totals", params: params).execute().value
        var spending: BudgetUsageCalculator.MonthlySpending = [:]
        for row in totals where row.type == "expense" {
            guard let id = row.categoryId,
                  SystemCategory.group(transferPairId: nil, systemKey: row.categories?.systemKey) == .operating
            else { continue }
            spending[id, default: [:]][row.date, default: 0] += row.amount
        }
        return spending
    }

    // MARK: - Generate + filter

    private func process(
        budgets: [RemoteBudget], usage: [UUID: BudgetUsage], debts: [RemoteDebt],
        recurring: [RemoteRecurringTransaction], goals: [RemoteSavingGoal], wallets: [RemoteWallet],
        states: [NotificationState], client: PostgrestClient, session: LocalDataStore.Session,
        today: String, debtHorizon: String, recurringHorizon: String, goalHorizon: String
    ) -> [AppNotification] {
        var notifs: [AppNotification] = []

        // Budget
        for b in budgets {
            guard let budget = usage[b.id] else { continue }
            let spent = budget.spent
            let limit = budget.effectiveAmount
            let name = b.categories?.displayName ?? "Budget"
            let icon = b.categories?.icon ?? "💰"
            if spent > limit {
                notifs.append(AppNotification(id: "budget_over:\(b.id)", type: "budget_over",
                    severity: .alert, title: "Budget exceeded",
                    message: "\(icon) \(name): \(fmt(spent)) / \(fmt(limit))",
                    destination: .budgets, isRead: false))
            } else if limit > 0, spent / limit >= 0.8 {
                notifs.append(AppNotification(id: "budget_near:\(b.id)", type: "budget_near",
                    severity: .warning, title: "Budget almost used",
                    message: "\(icon) \(name): \(Int(spent / limit * 100))% used",
                    destination: .budgets, isRead: false))
            }
        }

        // Debt
        for d in debts {
            guard d.remainingAmount > 0, let due = d.dueDate else { continue }
            if due < today {
                notifs.append(AppNotification(id: "debt_overdue:\(d.id):\(due)", type: "debt_overdue",
                    severity: .alert, title: "Debt overdue",
                    message: "\(d.personName) · \(fmt(d.remainingAmount))",
                    destination: .debts, isRead: false))
            } else if due <= debtHorizon {
                notifs.append(AppNotification(id: "debt_due:\(d.id):\(due)", type: "debt_due",
                    severity: .warning, title: "Debt due soon",
                    message: "\(d.personName) · \(fmt(d.remainingAmount)) · due \(due)",
                    destination: .debts, isRead: false))
            }
        }

        // Recurring
        for r in recurring {
            guard let nextRun = r.nextRunDate, nextRun <= recurringHorizon else { continue }
            if let end = r.endDate, end < nextRun { continue }
            let icon  = r.categories?.icon ?? "🔄"
            let label = (r.note?.isEmpty == false ? r.note : nil) ?? r.categories?.displayName ?? "Recurring"
            notifs.append(AppNotification(id: "recurring:\(r.id):\(nextRun)", type: "recurring_upcoming",
                severity: .info, title: "Upcoming recurring",
                message: "\(icon) \(label) · \(fmt(r.amount)) on \(nextRun)",
                destination: .recurring, isRead: false))
        }

        // Goals
        for g in goals {
            if g.targetAmount > 0, g.currentAmount >= g.targetAmount {
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
                    message: "\(g.icon ?? "🎯") \(g.name) · \(fmt(g.currentAmount)) / \(fmt(g.targetAmount))",
                    destination: .savingGoals, isRead: false))
            }
        }

        // Credit
        for w in wallets {
            guard let limit = w.creditLimit, limit > 0 else { continue }
            let used = limit - w.balance
            guard used / limit >= 0.8 else { continue }
            notifs.append(AppNotification(id: "credit:\(w.id)", type: "credit_high",
                severity: .warning, title: "Credit limit high",
                message: "\(w.name) · \(Int(used / limit * 100))% used",
                destination: .wallets, isRead: false))
        }

        // Apply states
        let stateById  = Dictionary(uniqueKeysWithValues: states.map { ($0.notification_id, $0) })
        let currentIds = Set(notifs.map { $0.id.lowercased() })

        let staleIds = states.map(\.notification_id).filter { !currentIds.contains($0.lowercased()) }
        if !staleIds.isEmpty {
            Task {
                do {
                    try LocalDataStore.validate(session)
                    try await client.from("notification_states")
                        .delete().eq("user_id", value: session.userId)
                        .in("notification_id", values: staleIds)
                        .execute()
                } catch is CancellationError {
                    return
                } catch {
                    NSLog("Unable to clean up stale notification states.")
                }
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

private struct NotificationState: Decodable, Identifiable {
    let notification_id: String
    let read_at: String?
    let dismissed_at: String?

    var id: String { notification_id }
}
