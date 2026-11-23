import Foundation
import Supabase

@MainActor
final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    // MARK: - Fetch

    func fetchNotifications(for session: LocalDataStore.Session) async throws -> [AppNotification] {
        let dataClient = try await LocalDataStore.authenticatedClient(for: session)
        let userId = session.userId
        let today = LedgerDate.string(from: Date())
        let calendar = LedgerDate.calendar
        let now = Date()
        guard let month = LedgerDate.startOfMonth(for: now),
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: month)
        else { return [] }
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
        let spending =
            currentBudgets.isEmpty
            ? [:]
            : try await budgetSpending(
                from: budgets.map(\.month).min() ?? monthStart, to: monthEnd, using: dataClient
            )
        let usage = BudgetUsageCalculator.calculate(budgets: budgets, spending: spending)
        let (debts, recurring, goals, wallets, states) = try await (
            debtsTask, recurringTask, goalsTask, walletsTask, statesTask
        )
        try LocalDataStore.validate(session)

        let notifications =
            budgetNotifications(currentBudgets, usage: usage)
            + debtNotifications(debts.filter { $0.status == "active" }, today: today, horizon: debtHorizon)
            + recurringNotifications(recurring.filter(\.active), horizon: recurringHorizon)
            + goalNotifications(goals.filter { $0.status == "active" }, today: today, horizon: goalHorizon)
            + creditNotifications(wallets.filter { $0.type == "credit" })

        await clearExpiredStates(states, currentIds: Set(notifications.map(\.id)), session: session, using: dataClient)
        try LocalDataStore.validate(session)
        let grouped = Dictionary(grouping: states) { $0.id.lowercased() }
        return notifications.compactMap { notice in
            let marks = grouped[notice.id, default: []]
            guard !marks.contains(where: { $0.dismissedAt != nil }) else { return nil }
            var result = notice
            result.isRead = marks.contains { $0.readAt != nil }
            return result
        }.sorted {
            if $0.isRead != $1.isRead { return !$0.isRead }
            return $0.severity.rawValue < $1.severity.rawValue
        }
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

    private func budgetNotifications(_ rows: [RemoteBudget], usage: [UUID: BudgetUsage]) -> [AppNotification] {
        rows.compactMap { row in
            guard let budget = usage[row.id] else { return nil }
            let exceeded = budget.spent > budget.effectiveAmount
            let ratio = budget.effectiveAmount > 0 ? budget.spent / budget.effectiveAmount : 0
            guard exceeded || ratio >= 0.8 else { return nil }
            return AppNotification(
                id: notificationID(exceeded ? "budget_over" : "budget_near", row.id),
                severity: exceeded ? .alert : .warning,
                title: exceeded ? "Budget exceeded" : "Budget almost used",
                message: { language in
                    let name = row.categories?.label(in: language) ?? language.text("Budget")
                    let icon = row.categories?.icon ?? "💰"
                    let spent = budget.spent.formatted(currency: "VND")
                    let limit = budget.effectiveAmount.formatted(currency: "VND")
                    return "\(icon) \(name): \(spent) / \(limit)"
                },
                destination: .budgets
            )
        }
    }

    private func debtNotifications(_ rows: [RemoteDebt], today: String, horizon: String) -> [AppNotification] {
        rows.compactMap { row in
            guard row.remainingAmount > 0, let due = row.dueDate, due <= horizon else { return nil }
            let overdue = due < today
            return AppNotification(
                id: notificationID(overdue ? "debt_overdue" : "debt_due", row.id, suffix: due),
                severity: overdue ? .alert : .warning,
                title: overdue ? "Debt overdue" : "Debt due soon",
                message: { language in
                    language.text(
                        "%@ · %@ · due %@", row.personName,
                        row.remainingAmount.formatted(currency: "VND"), Self.dateLabel(due, language))
                },
                destination: .debts
            )
        }
    }

    private func recurringNotifications(_ rows: [RemoteRecurringTransaction], horizon: String) -> [AppNotification] {
        rows.compactMap { row in
            guard let next = row.nextRunDate, next <= horizon, row.endDate.map({ next <= $0 }) ?? true else {
                return nil
            }
            return AppNotification(
                id: notificationID("recurring", row.id, suffix: next),
                severity: .info,
                title: "Upcoming recurring",
                message: { language in
                    let name =
                        (row.note?.isEmpty == false ? row.note : nil)
                        ?? row.categories?.label(in: language)
                        ?? language.text(row.type == "income" ? "Income" : "Expense")
                    let amount = row.amount.formatted(currency: "VND")
                    return language.text("%@ · %@ on %@", name, amount, Self.dateLabel(next, language))
                },
                destination: .recurring
            )
        }
    }

    private func goalNotifications(_ rows: [RemoteSavingGoal], today: String, horizon: String) -> [AppNotification] {
        rows.compactMap { row in
            if row.targetAmount > 0, row.currentAmount >= row.targetAmount {
                return AppNotification(
                    id: notificationID("goal_reached", row.id), severity: .success, title: "Goal reached!",
                    message: { _ in "\(row.icon ?? "🎯") \(row.name)" }, destination: .savingGoals
                )
            }
            guard let deadline = row.deadline, deadline <= horizon else { return nil }
            let overdue = deadline < today
            return AppNotification(
                id: notificationID("goal_deadline", row.id, suffix: "\(deadline):\(overdue ? "overdue" : "soon")"),
                severity: overdue ? .alert : .warning,
                title: overdue ? "Goal deadline passed" : "Goal deadline soon",
                message: { language in
                    language.text(
                        "%@ · %@ / %@ · due %@", row.name, row.currentAmount.formatted(currency: "VND"),
                        row.targetAmount.formatted(currency: "VND"), Self.dateLabel(deadline, language))
                },
                destination: .savingGoals
            )
        }
    }

    private func creditNotifications(_ rows: [RemoteWallet]) -> [AppNotification] {
        rows.compactMap { row in
            guard let limit = row.creditLimit, limit > 0 else { return nil }
            let usage = (limit - row.balance) / limit
            guard usage >= 0.8 else { return nil }
            return AppNotification(
                id: notificationID("credit", row.id), severity: .warning, title: "Credit limit high",
                message: { language in
                    let percent = usage.formatted(.percent.precision(.fractionLength(0)).locale(language.locale))
                    return language.text("%@ · %@ used", row.name, percent)
                },
                destination: .wallets
            )
        }
    }

    private func notificationID(_ prefix: String, _ id: UUID, suffix: String? = nil) -> String {
        ([prefix, id.uuidString.lowercased()] + (suffix.map { [$0] } ?? [])).joined(separator: ":")
    }

    private nonisolated static func dateLabel(_ value: String, _ language: AppLanguage) -> String {
        LedgerDate.date(from: value)?.formatted(LedgerDate.format(.dateTime.day().month()).locale(language.locale))
            ?? value
    }

    private func clearExpiredStates(
        _ states: [NotificationState], currentIds: Set<String>,
        session: LocalDataStore.Session, using client: PostgrestClient
    ) async {
        let families: Set<Substring> = [
            "budget_over", "budget_near", "debt_overdue", "debt_due", "recurring", "goal_reached", "goal_deadline",
            "credit",
        ]
        let stale = states.map(\.id).filter { id in
            guard let family = id.split(separator: ":", maxSplits: 1).first else { return false }
            return families.contains(family) && !currentIds.contains(id.lowercased())
        }
        guard !stale.isEmpty else { return }
        do {
            try LocalDataStore.validate(session)
            try await client.from("notification_states").delete().eq("user_id", value: session.userId)
                .in("notification_id", values: stale).execute()
        } catch is CancellationError {
            return
        } catch {
            NSLog("Unable to clean up stale notification states.")
        }
    }

    enum StateColumn: String {
        case read = "read_at"
        case dismissed = "dismissed_at"
    }

    func mark(_ ids: [String], as column: StateColumn, for session: LocalDataStore.Session) async throws {
        guard !ids.isEmpty else { return }
        let client = try await LocalDataStore.authenticatedClient(for: session)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let rows = Set(ids.map { $0.lowercased() }).map {
            ["user_id": session.userId.uuidString, "notification_id": $0, column.rawValue: timestamp]
        }
        try await client.from("notification_states").upsert(rows, onConflict: "user_id,notification_id").execute()
        try LocalDataStore.validate(session)
    }
}

private struct NotificationState: Decodable, Identifiable {
    let id: String
    let readAt: String?
    let dismissedAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "notification_id"
        case readAt = "read_at"
        case dismissedAt = "dismissed_at"
    }
}
