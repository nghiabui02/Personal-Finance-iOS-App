import Foundation
import OSLog
import Observation

/// Stores category membership metadata separately so the existing SwiftData schema can stay intact.
@MainActor
@Observable
final class CategoryDirectory {
    static let shared = CategoryDirectory()

    private struct Snapshot: Codable {
        let userId: UUID
        let memberships: [RemoteCategory]
    }

    private let logger = Logger(subsystem: "dev.nghiabui.personalfinance", category: "CategoryCache")
    private let fileURL = URL.applicationSupportDirectory.appending(path: "category-memberships.json")
    private(set) var memberships: [UUID: RemoteCategory] = [:]
    private var owner: UUID?

    private init() {}

    func prepare(for userId: UUID?) {
        owner = userId
        memberships = [:]
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: fileURL))
            if let userId, snapshot.userId == userId {
                memberships = Dictionary(
                    snapshot.memberships.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            } else {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            logger.error("Unable to prepare the category metadata cache.")
        }
    }

    func replace(with rows: [RemoteCategory]) {
        let next = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        guard next != memberships else { return }
        memberships = next
        save()
    }

    func merge(_ rows: [RemoteCategory]) {
        let changed = rows.filter { memberships[$0.id] != $0 }
        guard !changed.isEmpty else { return }
        for row in changed { memberships[row.id] = row }
        save()
    }

    func label(for id: UUID?, fallback: String?) -> String? {
        guard let id, let row = memberships[id] else { return fallback }
        return row.label(in: AppLocalization.shared.language)
    }

    private func save() {
        guard let owner else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Snapshot(userId: owner, memberships: Array(memberships.values)))
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch {
            logger.error("Unable to save the category metadata cache.")
        }
    }
}

extension LocalCategory {
    @MainActor var displayName: String {
        CategoryDirectory.shared.label(for: serverId, fallback: name) ?? name
    }

    @MainActor var isActiveMembership: Bool {
        CategoryDirectory.shared.memberships[serverId]?.isActive ?? true
    }
}

extension LocalTransaction {
    @MainActor var categoryLabel: String? {
        CategoryDirectory.shared.label(for: categoryId, fallback: categoryName)
    }
}

extension LocalBudget {
    @MainActor var categoryLabel: String {
        CategoryDirectory.shared.label(for: categoryId, fallback: categoryName) ?? categoryName
    }
}

extension LocalRecurringTransaction {
    @MainActor var categoryLabel: String? {
        CategoryDirectory.shared.label(for: categoryId, fallback: categoryName)
    }
}
