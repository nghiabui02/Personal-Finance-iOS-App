import Foundation
import SwiftData
import Testing
@testable import My_Finance

// Regression checks for bugs found in the November 2026 audit: an amount field that
// could save a number other than the one on screen, ledger days shifting with the
// device timezone, and an upgrade that wiped the offline cache.

struct AmountInputTests {

    private func type(_ input: String, over previous: Decimal) -> (text: String, amount: Decimal) {
        var amount = previous
        var text = input
        applyAmountFormat(new: input, amountText: &text, amount: &amount)
        return (text, amount)
    }

    @Test("should group digits and store the same value that is shown")
    func acceptsPlainDigits() {
        let result = type("1234567", over: 0)
        #expect(result.text == "1.234.567")
        #expect(result.amount == 1_234_567)
    }

    @Test("should accept a pasted amount that already has grouping separators")
    func acceptsSeparators() {
        #expect(type("200.000", over: 0).amount == 200_000)
        #expect(type("200,000", over: 0).amount == 200_000)
    }

    @Test("should drop the fraction of a pasted amount instead of multiplying it by 100")
    func dropsPastedFraction() {
        #expect(type("1,500,000.00", over: 0).amount == 1_500_000)
        #expect(type("1.500.000,5", over: 0).amount == 1_500_000)
    }

    @Test("should treat a backspace that leaves two digits after a separator as a deletion")
    func keepsDigitsOnBackspace() {
        var amount: Decimal = 12_345
        var text = "12.345"
        applyAmountFormat(old: "12.345", new: "12.34", amountText: &text, amount: &amount)
        #expect(amount == 1_234)
        #expect(text == "1.234")
    }

    @Test("should reject a negative amount instead of dropping the minus sign")
    func rejectsNegative() {
        let result = type("-200000", over: 5_000)
        #expect(result.amount == 5_000)
        #expect(result.text == "5.000")
    }

    @Test("should reject more digits than the field allows and keep the previous amount")
    func rejectsTooManyDigits() {
        let result = type("1234567890123", over: 5_000)
        #expect(result.amount == 5_000)
        #expect(result.text == "5.000")
        #expect(type("999999999999", over: 0).amount == 999_999_999_999)
    }

    @Test("should reject letters and non-ASCII digits")
    func rejectsNonDigits() {
        #expect(type("12a", over: 7).amount == 7)
        #expect(type("١٢٣", over: 7).amount == 7)
    }

    @Test("should clear the amount when the field is emptied")
    func clearsWhenEmpty() {
        let result = type("", over: 5_000)
        #expect(result.amount == 0)
        #expect(result.text.isEmpty)
    }
}

/// Swaps the process timezone, which `Calendar.current` follows, so the device sits
/// behind the ledger's Asia/Ho_Chi_Minh day.
@Suite(.serialized)
struct LedgerDayGroupingTests {

    private func withDeviceTimeZone(_ identifier: String, _ body: () -> Void) {
        let original = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: identifier) ?? original
        defer { NSTimeZone.default = original }
        body()
    }

    private func transaction(on day: String, type: TransactionKind, amount: Decimal, walletId: UUID) -> LocalTransaction {
        LocalTransaction(from: RemoteTransaction(
            id: UUID(), walletId: walletId, categoryId: nil, type: type, amount: amount, note: nil,
            transactionDate: LedgerDay(day)!, updatedAt: Date(), transferPairId: nil, bankFee: nil,
            categories: nil, wallets: nil, debtPaymentId: nil))
    }

    @Test("should group a transaction under its ledger day when the device is in another timezone")
    func groupsByLedgerDay() {
        let walletId = UUID()
        let november1 = transaction(on: "2026-11-01", type: .expense, amount: 1_000, walletId: walletId)
        withDeviceTimeZone("America/Los_Angeles") {
            let groups = TransactionGroupingCalculator.group([november1]).all
            #expect(groups.map { LedgerDate.string(from: $0.0) } == ["2026-11-01"])
        }
    }

    @Test("should count a wallet's monthly totals by ledger month when the device is in another timezone")
    func walletMonthByLedgerCalendar() throws {
        let walletId = UUID()
        let rows = [
            transaction(on: "2026-11-01", type: .income, amount: 300, walletId: walletId),
            transaction(on: "2026-10-31", type: .expense, amount: 50, walletId: walletId)
        ]
        let midNovember = try #require(LedgerDate.date(from: "2026-11-15"))
        withDeviceTimeZone("America/Los_Angeles") {
            let metrics = WalletDetailMetricsCalculator.calculate(
                transactions: rows, walletId: walletId, referenceDate: midNovember)
            #expect(metrics.monthlyIncome == 300)
            #expect(metrics.monthlyExpense == 0)
        }
    }
}

/// The cache schema as the previous release stored it: kinds in `type`, money as `Double`.
private enum PreviousCacheSchema {
    @Model final class LocalWallet {
        var serverId: UUID
        var name: String
        var type: String
        var balance: Double
        var isDefault: Bool
        var color: String?
        var icon: String?
        var updatedAt: Date
        var creditLimit: Double?
        var statementDay: Int?
        var paymentDueDay: Int?

        init(serverId: UUID) {
            self.serverId = serverId
            name = "Card"; type = "credit"; balance = 1_250_000; isDefault = true
            updatedAt = Date(); creditLimit = 5_000_000
        }
    }
}

struct CacheMigrationTests {

    @Test("should keep cached wallets when the app upgrades to the current schema")
    func previousStoreOpensInPlace() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "cache.store")
        let walletId = UUID()

        do {
            let previous = try ModelContainer(
                for: PreviousCacheSchema.LocalWallet.self, configurations: ModelConfiguration(url: storeURL))
            let context = ModelContext(previous)
            context.insert(PreviousCacheSchema.LocalWallet(serverId: walletId))
            try context.save()
        }

        let current = try ModelContainer(for: LocalWallet.self, configurations: ModelConfiguration(url: storeURL))
        let wallets = try ModelContext(current).fetch(FetchDescriptor<LocalWallet>())
        let wallet = try #require(wallets.first)
        #expect(wallets.count == 1)
        #expect(wallet.serverId == walletId)
        #expect(wallet.type == .credit)
        #expect(wallet.balance == 1_250_000)
        #expect(wallet.creditLimit == 5_000_000)
    }
}
