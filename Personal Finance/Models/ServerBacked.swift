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
    /// Rows whose `serverId` is in `ids`. Each model spells out its own `#Predicate`:
    /// SwiftData cannot translate a key path reached through this protocol.
    static func withServerIds(_ ids: [UUID]) -> FetchDescriptor<Self>
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
    static func withServerIds(_ ids: [UUID]) -> FetchDescriptor<LocalWallet> {
        FetchDescriptor(predicate: #Predicate { ids.contains($0.serverId) })
    }
}

extension LocalCategory: ServerBacked {
    static func remoteId(_ remote: RemoteCategory) -> UUID { remote.id }
    static func withServerIds(_ ids: [UUID]) -> FetchDescriptor<LocalCategory> {
        FetchDescriptor(predicate: #Predicate { ids.contains($0.serverId) })
    }
}

extension LocalDebt: ServerBacked {
    static func remoteId(_ remote: RemoteDebt) -> UUID { remote.id }
    static func withServerIds(_ ids: [UUID]) -> FetchDescriptor<LocalDebt> {
        FetchDescriptor(predicate: #Predicate { ids.contains($0.serverId) })
    }
}

extension LocalSavingGoal: ServerBacked {
    static func remoteId(_ remote: RemoteSavingGoal) -> UUID { remote.id }
    static func withServerIds(_ ids: [UUID]) -> FetchDescriptor<LocalSavingGoal> {
        FetchDescriptor(predicate: #Predicate { ids.contains($0.serverId) })
    }
}

extension LocalRecurringTransaction: ServerBacked {
    static func remoteId(_ remote: RemoteRecurringTransaction) -> UUID { remote.id }
    static func withServerIds(_ ids: [UUID]) -> FetchDescriptor<LocalRecurringTransaction> {
        FetchDescriptor(predicate: #Predicate { ids.contains($0.serverId) })
    }
}

extension LocalTransaction: ServerBacked {
    static func remoteId(_ remote: RemoteTransaction) -> UUID { remote.id }
    static func withServerIds(_ ids: [UUID]) -> FetchDescriptor<LocalTransaction> {
        FetchDescriptor(predicate: #Predicate { ids.contains($0.serverId) })
    }
}

extension LocalBudget: ServerBacked {
    static func remoteId(_ remote: RemoteBudget) -> UUID { remote.id }
    static func withServerIds(_ ids: [UUID]) -> FetchDescriptor<LocalBudget> {
        FetchDescriptor(predicate: #Predicate { ids.contains($0.serverId) })
    }
}
