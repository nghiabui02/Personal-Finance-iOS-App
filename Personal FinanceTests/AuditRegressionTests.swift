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

