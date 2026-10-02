import Foundation

/// Shapes returned by the money RPCs.
///
/// Every balance-changing operation runs as one Postgres function inside a single
/// transaction and answers with the same envelope: the rows it wrote, the wallets
/// whose balance moved, and what it removed. The local store can therefore be
/// brought back in step without re-querying.
enum RPC {
    /// A wallet whose balance the server just changed. Nothing else about the
    /// wallet moves, so only the new balance comes back.
    struct WalletBalance: Decodable {
        let id: UUID
        let balance: Double
    }

    /// One shape for all ten functions.
    ///
    /// Each function fills in the subset it has something to say about and omits
    /// the rest. A single type is deliberate: separate per-function structs kept
    /// silently dropping a key the function did return — a debt left stale after
    /// deleting its payment, transfer rows never inserted after deleting a wallet —
    /// and nothing failed loudly when they did.
    ///
    /// The server also returns `debt_payments`, which is not decoded here: payment
    /// history has no local model and is read straight from the server each time
    /// the debt detail screen opens, so there is nothing to keep in step.
    struct Envelope: Decodable {
        /// Rows created or updated, already carrying their category and wallet.
        let transactions: [RemoteTransaction]
        /// Wallets whose balance changed.
        let wallets: [WalletBalance]
        /// The debt this operation moved, as a full row.
        let debt: RemoteDebt?
        let deletedTransactionIds: [UUID]
        let deletedDebtPaymentIds: [UUID]
        let deletedWalletIds: [UUID]

        /// Reported by `record_debt_payment` when the payment cleared the debt.
        let settled: Bool?
        /// Reported by `pay_credit_card`.
        let newAvailableCredit: Double?
        /// Reported by `reconcile_wallet`; `0` means nothing needed recording.
        let delta: Double?

        enum CodingKeys: String, CodingKey {
            case transactions, wallets, debt, settled, delta
            case deletedTransactionIds = "deleted_transaction_ids"
            case deletedDebtPaymentIds = "deleted_debt_payment_ids"
            case deletedWalletIds = "deleted_wallet_ids"
            case newAvailableCredit = "new_available_credit"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            transactions = try c.decodeIfPresent([RemoteTransaction].self, forKey: .transactions) ?? []
            wallets = try c.decodeIfPresent([WalletBalance].self, forKey: .wallets) ?? []
            debt = try c.decodeIfPresent(RemoteDebt.self, forKey: .debt)
            deletedTransactionIds = try c.decodeIfPresent([UUID].self, forKey: .deletedTransactionIds) ?? []
            deletedDebtPaymentIds = try c.decodeIfPresent([UUID].self, forKey: .deletedDebtPaymentIds) ?? []
            deletedWalletIds = try c.decodeIfPresent([UUID].self, forKey: .deletedWalletIds) ?? []
            settled = try c.decodeIfPresent(Bool.self, forKey: .settled)
            newAvailableCredit = try c.decodeIfPresent(Double.self, forKey: .newAvailableCredit)
            delta = try c.decodeIfPresent(Double.self, forKey: .delta)
        }
    }
}
