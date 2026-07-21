import Foundation

@MainActor
final class NotificationViewModel: ObservableObject {
    @Published var notifications: [AppNotification] = []
    @Published var isLoading = false
    @Published var errorMsg: String?

    var unreadCount: Int { notifications.filter { !$0.isRead }.count }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            notifications = try await NotificationService.shared.fetchNotifications()
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    // Call when sheet opens — marks all as read on server but keeps visual state for this session
    func markAllReadRemote() {
        let unreadIds = notifications.filter { !$0.isRead }.map { $0.id }
        guard !unreadIds.isEmpty else { return }
        Task { try? await NotificationService.shared.markRead(ids: unreadIds) }
    }

    // Call when sheet closes — update local read state so badge clears
    func applyLocalRead() {
        for i in notifications.indices { notifications[i].isRead = true }
    }

    func dismiss(_ notif: AppNotification) {
        notifications.removeAll { $0.id == notif.id }
        Task { try? await NotificationService.shared.dismiss(ids: [notif.id]) }
    }
}
