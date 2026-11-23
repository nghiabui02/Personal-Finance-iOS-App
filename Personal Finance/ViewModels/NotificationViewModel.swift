import Foundation

@MainActor
final class NotificationViewModel: ObservableObject {
    @Published private(set) var notifications: [AppNotification] = []
    @Published private(set) var isLoading = false
    @Published var errorMsg: String?

    private var isMarkingRead = false

    var unreadCount: Int { notifications.filter { !$0.isRead }.count }

    func load() async {
        guard !isLoading, let session = LocalDataStore.session else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            notifications = try await NotificationService.shared.fetchNotifications(for: session)
        } catch is CancellationError {
            return
        } catch {
            errorMsg = error.asDisplayableError().localizedDescription
        }
    }

    func markAllRead() async {
        let ids = Set(notifications.filter { !$0.isRead }.map(\.id))
        guard let session = LocalDataStore.session, !ids.isEmpty, !isMarkingRead else { return }
        isMarkingRead = true
        defer { isMarkingRead = false }
        do {
            try await NotificationService.shared.mark(Array(ids), as: .read, for: session)
            for index in notifications.indices where ids.contains(notifications[index].id) {
                notifications[index].isRead = true
            }
        } catch is CancellationError {
            return
        } catch {
            errorMsg = error.asDisplayableError().localizedDescription
        }
    }

    func dismiss(_ notice: AppNotification, for session: LocalDataStore.Session) async {
        do {
            try await NotificationService.shared.mark([notice.id], as: .dismissed, for: session)
            notifications.removeAll { $0.id == notice.id }
        } catch is CancellationError {
            return
        } catch {
            errorMsg = error.asDisplayableError().localizedDescription
        }
    }
}
