import Foundation
import SwiftData

/// A local model that mirrors one server row, keyed by `serverId`.
///
/// Conforming lets `SyncManager` reconcile any table the same way, which matters
/// because the three steps — update what changed, insert what is new, remove what
/// the server no longer has — only work as a set. Five of these tables used to
/// skip the removal step, so a row deleted on another device stayed on this one
/// forever, sitting next to its replacement.
protocol ServerBacked: PersistentModel {
    associatedtype Remote
    var serverId: UUID { get }
    static func remoteId(_ remote: Remote) -> UUID
    init(from remote: Remote)
    func update(from remote: Remote)
}

extension ServerBacked {
    /// Assigns only a value that differs.
    ///
    /// SwiftData marks a model changed on every assignment, even of the same value, so
    /// re-applying unchanged server rows on each sync rewrote every row on save and
    /// refreshed every `@Query` although nothing had moved.
    func setIfChanged<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<Self, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }
}

extension LocalWallet: ServerBacked {
    static func remoteId(_ remote: RemoteWallet) -> UUID { remote.id }
}

extension LocalCategory: ServerBacked {
    static func remoteId(_ remote: RemoteCategory) -> UUID { remote.id }
}

extension LocalDebt: ServerBacked {
    static func remoteId(_ remote: RemoteDebt) -> UUID { remote.id }
}

extension LocalSavingGoal: ServerBacked {
    static func remoteId(_ remote: RemoteSavingGoal) -> UUID { remote.id }
}

extension LocalRecurringTransaction: ServerBacked {
    static func remoteId(_ remote: RemoteRecurringTransaction) -> UUID { remote.id }
}

extension LocalTransaction: ServerBacked {
    static func remoteId(_ remote: RemoteTransaction) -> UUID { remote.id }
}

extension LocalBudget: ServerBacked {
    static func remoteId(_ remote: RemoteBudget) -> UUID { remote.id }
}
