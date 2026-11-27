import Foundation
import Testing
@testable import My_Finance

// Regression checks for the fixes from the November 2026 review: duplicate money writes,
// fields that could not be cleared, totals that disagreed, and dates and strings that
// ignored the app's time zone and language.

/// A money write retried after a lost response must reuse its `p_client_request_id`,
/// and edited content must not, or the server replays the old result.
@MainActor
struct ClientRequestIDTests {

    private struct Payment: Encodable, Sendable { let p_amount: Decimal; let p_note: String? }

    private let function = "create_transaction"
    /// Unique per test, so tests running in parallel never share a pending id.
    private let userId = UUID()

    @Test("should reuse the id when the same content is retried")
    func reusesIdOnRetry() throws {
        let first = try ClientRequestID.id(for: function, userId: userId, params: Payment(p_amount: 50_000, p_note: "Coffee"))
        let retry = try ClientRequestID.id(for: function, userId: userId, params: Payment(p_amount: 50_000, p_note: "Coffee"))
        #expect(first != nil)
        #expect(retry == first)
    }

    @Test("should issue a new id when the content changes")
    func newIdWhenContentChanges() throws {
        let first = try ClientRequestID.id(for: function, userId: userId, params: Payment(p_amount: 50_000, p_note: nil))
        let edited = try ClientRequestID.id(for: function, userId: userId, params: Payment(p_amount: 60_000, p_note: nil))
        #expect(edited != first)
    }

    @Test("should issue a new id for the same content after a success")
    func newIdAfterSuccess() throws {
        let payment = Payment(p_amount: 50_000, p_note: nil)
        let first = try ClientRequestID.id(for: function, userId: userId, params: payment)
        ClientRequestID.finish(function)
        #expect(try ClientRequestID.id(for: function, userId: userId, params: payment) != first)
    }

    @Test("should issue a new id when another user sends the same content")
    func newIdForAnotherUser() throws {
        let payment = Payment(p_amount: 50_000, p_note: nil)
        let first = try ClientRequestID.id(for: function, userId: userId, params: payment)
        #expect(try ClientRequestID.id(for: function, userId: UUID(), params: payment) != first)
    }

    @Test("should not send an id to a function the server has not made idempotent")
    func noIdForOtherFunctions() throws {
        #expect(try ClientRequestID.id(for: "update_transaction", userId: userId, params: Payment(p_amount: 1, p_note: nil)) == nil)
    }

    @Test("should add p_client_request_id next to the function's own arguments")
    func encodesIdBesideParams() throws {
        let id = UUID()
        let data = try JSONEncoder().encode(ClientRequestParams(params: Payment(p_amount: 50_000, p_note: nil), clientRequestId: id))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["p_amount"] as? Int == 50_000)
        #expect(json["p_client_request_id"] as? String == id.uuidString)
        #expect(json["p_note"] == nil)
    }

    @Test("should leave the arguments unchanged when there is no id")
    func encodesWithoutId() throws {
        let data = try JSONEncoder().encode(ClientRequestParams(params: Payment(p_amount: 1, p_note: nil), clientRequestId: nil))
        #expect(String(bytes: data, encoding: .utf8) == #"{"p_amount":1}"#)
    }
}

/// Edits that clear a field must reach the server as `null`, or the old value silently stays.
struct ClearedFieldEncodingTests {

    private func json(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("should send null for a debt's cleared due date, note and contact")
    func debtClearsOptionalFields() throws {
        let body = try json(DebtUpdate(person_name: "An", person_contact: nil, due_date: nil, note: nil, status: .active))
        for key in ["person_contact", "due_date", "note"] {
            #expect(body[key] is NSNull, "\(key) should be an explicit null")
        }
    }

    @Test("should send null for a goal's cleared deadline, note and icon")
    func goalClearsOptionalFields() throws {
        let body = try json(GoalUpdate(name: "Trip", icon: nil, target_amount: 1_000_000, deadline: nil, note: nil))
        for key in ["icon", "deadline", "note"] {
            #expect(body[key] is NSNull, "\(key) should be an explicit null")
        }
    }
}

struct DebtStatusEditingTests {

    @Test("should keep an overdue debt overdue when only its details are edited")
    func keepsOverdue() {
        #expect(DebtStatus.overdue.editing(markCompleted: false) == .overdue)
    }

    @Test("should reopen a completed debt as active when the toggle is turned off")
    func reopensCompleted() {
        #expect(DebtStatus.completed.editing(markCompleted: false) == .active)
    }

    @Test("should mark any debt completed when the toggle is on")
    func marksCompleted() {
        #expect(DebtStatus.overdue.editing(markCompleted: true) == .completed)
        #expect(DebtStatus.active.editing(markCompleted: true) == .completed)
    }
}

@MainActor
struct RowInsertIDTests {

    private struct Rule: Encodable { var id: UUID?; let amount: Decimal }
    private let userId = UUID()

    @Test("should reuse a new row's id when the same rule is saved again after a lost response")
    func reusesRowId() throws {
        let rule = Rule(id: nil, amount: 100_000)
        let first = try ClientRequestID.reusableId(for: "recurring_transactions", userId: userId, params: rule)
        let retry = try ClientRequestID.reusableId(for: "recurring_transactions", userId: userId, params: rule)
        #expect(retry == first)
    }
}

@MainActor
private func ledgerTransaction(_ amount: Decimal, category: UUID?, on day: String) throws -> LocalTransaction {
    let categoryJSON = category.map { "\"\($0.uuidString)\"" } ?? "null"
    let json = """
    {"id":"\(UUID().uuidString)","type":"expense","amount":\(amount),"transaction_date":"\(day)",
     "updated_at":"2026-11-01T00:00:00Z","user_category_id":\(categoryJSON)}
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return LocalTransaction(from: try decoder.decode(RemoteTransaction.self, from: Data(json.utf8)))
}

@MainActor
struct SpendingShareTests {

    @Test("should give each category its share of all spending, not of the top five")
    func sharesOfAllSpending() throws {
        let transactions = try (0..<6).map { _ in try ledgerTransaction(100_000, category: UUID(), on: "2026-11-03") }
        let month = try #require(LedgerDate.date(from: "2026-11-01"))
        let metrics = DashboardMetricsCalculator.calculate(
            transactions: transactions, categories: [], wallets: [], budgets: [], debts: [],
            selectedMonth: month, currency: "VND"
        )
        #expect(metrics.spendingItems.count == 5)
        for item in metrics.spendingItems {
            #expect(abs(item.percentage - 100.0 / 6) < 0.01)
        }
        #expect(Set(metrics.spendingItems.map(\.id)).count == metrics.spendingItems.count)
    }
}

@MainActor
struct DayHeaderTotalsTests {

    @Test("should key day totals the same way the list groups its days, so each header finds its total")
    func headersFindTheirTotals() throws {
        let transactions = try ["2026-11-03", "2026-11-03", "2026-11-04"].map {
            try ledgerTransaction(50_000, category: nil, on: $0)
        }
        let totals = TransactionPeriodTotalsCalculator.dailyTotals(from: transactions)
        for (day, rows) in TransactionGroupingCalculator.group(transactions).all {
            let total = try #require(totals[day])
            #expect(total.expense == rows.reduce(0) { $0 + $1.amount })
        }
    }
}

