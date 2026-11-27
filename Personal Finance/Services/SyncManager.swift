import Foundation
import Network
import Observation
import OSLog
import Supabase
import SwiftData

/// `@Observable` so a screen re-renders only for the sync fields it reads — with
/// `ObservableObject`, every `isSyncing` flip rebuilt every tab's metrics.
@MainActor
@Observable
final class SyncManager {
    static let shared = SyncManager()

    private(set) var isOnline = true
    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?
    private(set) var syncError: String?
    private(set) var netWorthSnapshots: [RemoteNetWorthSnapshot] = []

    private let logger = Logger(subsystem: "dev.nghiabui.personalfinance", category: "LedgerSync")
    /// Intervals for Instruments' os_signpost track: "Download ledger" and "Apply ledger".
    private let signposter = OSSignposter(subsystem: "dev.nghiabui.personalfinance", category: "LedgerSync")
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.nghiabui.pf.network")
    @ObservationIgnored private var pendingContext: ModelContext?
    @ObservationIgnored private var runningSession: LocalDataStore.Session?

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = connected
                if wasOffline && connected {
                    NotificationCenter.default.post(name: .networkRestored, object: nil)
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    func clearSyncState() {
        pendingContext = nil
        lastSyncDate = nil
        syncError = nil
        netWorthSnapshots = []
    }

    func requestSync(modelContext: ModelContext) {
        pendingContext = modelContext
        resumePendingSync()
    }

    func resumePendingSync() {
        guard !isSyncing, !LocalDataStore.isMutating, let context = pendingContext else { return }
        pendingContext = nil
        Task { await syncAll(modelContext: context) }
    }

    func syncAll(modelContext: ModelContext) async {
        guard let session = LocalDataStore.session else { return }
        if isSyncing {
            if runningSession != session { pendingContext = modelContext }
            return
        }
        guard !LocalDataStore.isMutating else {
            pendingContext = modelContext
            return
        }
        isSyncing = true
        runningSession = session
        syncError = nil
        defer {
            isSyncing = false
            runningSession = nil
            resumePendingSync()
        }

        let revision = LocalDataStore.revision
        do {
            let client = try await LocalDataStore.authenticatedClient(for: session)
            let download = try await download(for: session, using: client)
            try Task.checkCancellation()
            try LocalDataStore.validate(session)
            guard revision == LocalDataStore.revision, !LocalDataStore.isMutating else {
                pendingContext = modelContext
                return
            }

            try apply(download, for: session, in: modelContext)
            lastSyncDate = Date()
            do {
                try await recordSnapshot(from: modelContext, for: session, using: client)
            } catch is CancellationError {
                return
            } catch {
                logger.error("Unable to record the net worth snapshot: \(String(describing: type(of: error)))")
            }

        } catch is CancellationError {
            return
        } catch {
            guard LocalDataStore.session == session else { return }
            syncError =
                isOnline
                ? error.asDisplayableError().localizedDescription
                : AppLocalization.shared.language.text("No internet connection. Data may be outdated.")
            logger.error("Unable to sync the ledger: \(String(describing: type(of: error)))")
        }
    }

    /// Only what changed since the last sync, falling back to everything when there is no
    /// cursor, the daily full download is due, or the server cannot answer a delta yet.
    private func download(
        for session: LocalDataStore.Session, using client: PostgrestClient
    ) async throws -> LedgerDownload {
        let interval = signposter.beginInterval("Download ledger")
        defer { signposter.endInterval("Download ledger", interval) }
        let clock = try await serverClock(using: client)
        if let clock, let cursor = SyncCursor.load(for: session.userId), !cursor.isDueForFullSync {
            do {
                let changes = try await LedgerChanges.fetch(client: client, userId: session.userId, since: cursor.since)
                return .delta(changes, clock: clock, previous: cursor)
            } catch let error as PostgrestError {
                logger.error("Delta sync failed (\(error.code ?? "no code", privacy: .public)), downloading all rows")
            }
        }
        return .full(try await Ledger.fetch(client: client, userId: session.userId), clock: clock)
    }

    /// The server's time as this download starts, or `nil` while the delta-sync migration
    /// has not reached the database — then no cursor is kept, so the first sync after it
    /// lands is a full one and no deletion from before the log existed is missed.
    private func serverClock(using client: PostgrestClient) async throws -> Date? {
        do {
            return try await client.rpc("sync_clock").execute().value
        } catch let error as PostgrestError {
            logger.error("sync_clock unavailable (\(error.code ?? "no code", privacy: .public))")
            return nil
        }
    }

    private func apply(_ download: LedgerDownload, for session: LocalDataStore.Session, in context: ModelContext) throws {
        let interval = signposter.beginInterval("Apply ledger")
        defer { signposter.endInterval("Apply ledger", interval) }
        let cursor: SyncCursor?
        switch download {
        case .full(let ledger, let clock):
            try ledger.apply(in: context)
            CategoryDirectory.shared.replace(with: ledger.categories)
            netWorthSnapshots = ledger.snapshots
            cursor = clock.map { SyncCursor(since: $0, lastFullSync: Date()) }
        case .delta(let changes, let clock, let previous):
            try changes.apply(in: context)
            CategoryDirectory.shared.merge(changes.categories)
            netWorthSnapshots = changes.snapshots
            cursor = SyncCursor(since: clock, lastFullSync: previous.lastFullSync)
        }
        do {
            try cursor?.save(for: session.userId)
        } catch {
            // Losing the cursor only costs a full download next time.
            logger.error("Unable to save the sync cursor: \(String(describing: error), privacy: .public)")
        }
    }

    private func recordSnapshot(
        from context: ModelContext, for session: LocalDataStore.Session, using client: PostgrestClient
    ) async throws {
        let wallets = try context.fetch(FetchDescriptor<LocalWallet>())
        let debts = try context.fetch(FetchDescriptor<LocalDebt>())
        guard !wallets.isEmpty || !debts.isEmpty || !netWorthSnapshots.isEmpty else { return }
        try LocalDataStore.validate(session)
        let today = LedgerDate.string(from: Date())
        let netWorth = NetWorth.calculate(wallets: wallets, debts: debts).total
        guard netWorthSnapshots.first(where: { $0.recordedDate.string == today })?.netWorth != netWorth else { return }
        struct Body: Encodable { let user_id: UUID, recorded_date: String, net_worth: Decimal }
        let body = Body(user_id: session.userId, recorded_date: today, net_worth: netWorth)
        let row: RemoteNetWorthSnapshot = try await client.from("net_worth_snapshots")
            .upsert(body, onConflict: "user_id,recorded_date").select().single().execute().value
        try LocalDataStore.validate(session)
        netWorthSnapshots.removeAll { $0.recordedDate.string == today }
        netWorthSnapshots.append(row)
    }

}

private enum LedgerDownload {
    case full(Ledger, clock: Date?)
    case delta(LedgerChanges, clock: Date, previous: SyncCursor)
}

private struct Ledger {
    let wallets: [RemoteWallet]
    let categories: [RemoteCategory]
    let transactions: [RemoteTransaction]
    let budgets: [RemoteBudget]
    let debts: [RemoteDebt]
    let goals: [RemoteSavingGoal]
    let recurring: [RemoteRecurringTransaction]
    let snapshots: [RemoteNetWorthSnapshot]

    static func fetch(client: PostgrestClient, userId: UUID) async throws -> Self {
        async let wallets: [RemoteWallet] = client.readOwnedRows("wallets", userId: userId)
        async let categories: [RemoteCategory] = client.readOwnedRows(
            "user_categories", columns: CategoryProjection.membership, userId: userId)
        async let transactions: [RemoteTransaction] = client.readOwnedRows(
            "transactions", columns: CategoryProjection.withWallet, userId: userId)
        async let budgets: [RemoteBudget] = client.readOwnedRows(
            "budgets", columns: CategoryProjection.withCategory, userId: userId)
        async let debts: [RemoteDebt] = client.readOwnedRows("debts", userId: userId)
        async let goals: [RemoteSavingGoal] = client.readOwnedRows("saving_goals", userId: userId)
        async let recurring: [RemoteRecurringTransaction] = client.readOwnedRows(
            "recurring_transactions", columns: CategoryProjection.withWallet, userId: userId)
        async let snapshots = client.readNetWorthHistory(userId: userId)
        return try await Self(
            wallets: wallets, categories: categories, transactions: transactions, budgets: budgets,
            debts: debts, goals: goals, recurring: recurring, snapshots: snapshots)
    }

    @MainActor
    func apply(in context: ModelContext) throws {
        do {
            try reconcile(LocalWallet.self, with: wallets, in: context)
            try reconcile(LocalCategory.self, with: categories, in: context)
            try reconcile(LocalTransaction.self, with: transactions, in: context)
            try reconcile(LocalBudget.self, with: budgets, in: context)
            try reconcile(LocalDebt.self, with: debts, in: context)
            try reconcile(LocalSavingGoal.self, with: goals, in: context)
            try reconcile(LocalRecurringTransaction.self, with: recurring, in: context)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    @MainActor
    private func reconcile<Model: ServerBacked>(
        _ type: Model.Type, with remotes: [Model.Remote], in context: ModelContext
    ) throws {
        let remoteIds = Set(remotes.map(Model.remoteId))
        var localById: [UUID: Model] = [:]
        for local in try context.fetch(FetchDescriptor<Model>()) {
            if !remoteIds.contains(local.serverId) || localById[local.serverId] != nil {
                context.delete(local)
            } else {
                localById[local.serverId] = local
            }
        }
        for remote in remotes {
            if let local = localById[Model.remoteId(remote)] {
                local.update(from: remote)
            } else {
                context.insert(Model(from: remote))
            }
        }
    }
}

extension PostgrestClient {
    /// Walk by UUID so a removed row cannot shift the next page past other rows.
    func readOwnedRows<Row: Decodable & Identifiable>(
        _ table: String, columns: String = "*", userId: UUID, idColumn: String = "id"
    ) async throws -> [Row] where Row.ID: PostgrestFilterValue {
        try await readRows(idColumn: idColumn) {
            from(table).select(columns).eq("user_id", value: userId)
        }
    }

    func readNetWorthHistory(userId: UUID) async throws -> [RemoteNetWorthSnapshot] {
        let firstDay = NetWorthHistory.firstDay()
        return try await readRows {
            from("net_worth_snapshots").select().eq("user_id", value: userId).gte("recorded_date", value: firstDay)
        }
    }

    func readRows<Row: Decodable & Identifiable>(
        idColumn: String = "id", matching query: @Sendable () -> PostgrestFilterBuilder
    ) async throws -> [Row] where Row.ID: PostgrestFilterValue {
        let pageSize = 500
        var rows: [Row] = []
        while true {
            try Task.checkCancellation()
            let base = query()
            let pageQuery = rows.last.map { base.gt(idColumn, value: $0.id) } ?? base
            let page: [Row] = try await pageQuery.order(idColumn, ascending: true).limit(pageSize).execute().value
            // An empty page, even after a short page, is the end regardless of the server's row cap.
            guard !page.isEmpty else { return rows }
            rows.append(contentsOf: page)
        }
    }
}

extension Notification.Name {
    static let networkRestored = Notification.Name("com.nghiabui.pf.networkRestored")
}
