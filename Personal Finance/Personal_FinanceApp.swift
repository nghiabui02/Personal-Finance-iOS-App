import OSLog
import SwiftData
import SwiftUI

private let storeLogger = Logger(subsystem: "dev.nghiabui.personalfinance", category: "LocalStore")

@main
struct PersonalFinanceApp: App {
    let modelContainer: ModelContainer = {
        let schema = Schema([
            LocalWallet.self,
            LocalCategory.self,
            LocalTransaction.self,
            LocalBudget.self,
            LocalDebt.self,
            LocalSavingGoal.self,
            LocalRecurringTransaction.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        Self.excludeCachesFromBackup()
        // A store that does not exist yet (first launch, or a device restored from a backup
        // that left the cache out) holds none of the rows the saved sync cursors describe.
        if !FileManager.default.fileExists(atPath: config.url.path) {
            SyncCursor.resetAll()
        }
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            Self.protectStore(at: config.url)
            return container
        } catch {
            // Migration failed (schema change) — wipe local cache; data re-syncs from Supabase
            storeLogger.error("Local store could not open, rebuilding it: \(String(describing: error))")
            Self.removeStore(at: config.url)
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }
    }()

    /// Everything under Application Support is a cache the next sync downloads again (the
    /// SwiftData store and the category metadata), so it stays out of device backups instead
    /// of leaving a copy of the user's finances in iCloud or on a computer. Flagging the
    /// folder rather than each file also covers SQLite's `-wal`/`-shm` and files replaced
    /// by atomic writes, which would not keep a per-file flag.
    /// Anything that must survive a restore belongs somewhere else.
    private static func excludeCachesFromBackup() {
        var directory = URL.applicationSupportDirectory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
        } catch {
            storeLogger.error("Unable to exclude the local cache from backups: \(String(describing: error))")
        }
    }

    /// SQLite keeps recent writes in `-wal` and `-shm` beside the store, so every
    /// operation on the store has to cover all three files.
    private static func storeFiles(at url: URL) -> [URL] {
        [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")]
    }

    private static func protectStore(at url: URL) {
        for file in storeFiles(at: url) where FileManager.default.fileExists(atPath: file.path) {
            do {
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: file.path)
            } catch {
                storeLogger.error("Unable to protect \(file.lastPathComponent): \(String(describing: error))")
            }
        }
    }

    /// A leftover `-wal` would be replayed into the fresh, empty store and corrupt it.
    /// Sync cursors go too, or the next sync would only fetch changes into an empty store.
    private static func removeStore(at url: URL) {
        SyncCursor.resetAll()
        for file in storeFiles(at: url) where FileManager.default.fileExists(atPath: file.path) {
            do {
                try FileManager.default.removeItem(at: file)
            } catch {
                storeLogger.error("Unable to remove \(file.lastPathComponent): \(String(describing: error))")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}
