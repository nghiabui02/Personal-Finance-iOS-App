import SwiftUI

struct NotificationsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: NotificationViewModel

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.notifications.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.notifications.isEmpty {
                    emptyState
                } else {
                    notificationList
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            await vm.load()
            await vm.markAllRead()
        }
        .onChange(of: vm.isLoading) { _, loading in
            if !loading { Task { await vm.markAllRead() } }
        }
        .errorAlert($vm.errorMsg)
    }

    private var notificationList: some View {
        List {
            ForEach(vm.notifications) { notif in
                NotificationRow(notif: notif) {
                    guard let session = LocalDataStore.session else { return }
                    Task { await vm.dismiss(notif, for: session) }
                }
                    .listRowBackground(
                        notif.isRead
                            ? Color(.secondarySystemGroupedBackground)
                            : notif.severity.color.opacity(0.08)
                    )
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await vm.load() }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Notifications",
            systemImage: "bell.slash",
            description: Text("You're all caught up!")
        )
    }
}

// MARK: - Row

private struct NotificationRow: View {
    let notif: AppNotification
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notif.severity.icon)
                .font(.system(size: 18, weight: .semibold))
                .accessibilityHidden(true)
                .foregroundStyle(notif.severity.color)
                .frame(width: 26, height: 26)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(notif.title)
                    .font(.subheadline.weight(notif.isRead ? .regular : .semibold))
                    .foregroundStyle(notif.isRead ? .secondary : .primary)
                Text(notif.message(AppLocalization.shared.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(notif.destination.label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(notif.severity.color)
                    .padding(.top, 1)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .opacity(notif.isRead ? 0.65 : 1)
    }
}

// MARK: - Bell button (used in AppScreenHeaderModifier)

struct NotificationBellButton: View {
    @ObservedObject var vm: NotificationViewModel
    @State private var showSheet = false

    var body: some View {
        Button { showSheet = true } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(size: 17, weight: .semibold))
                if vm.unreadCount > 0 {
                    Text(vm.unreadCount > 9 ? "9+" : "\(vm.unreadCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, vm.unreadCount > 9 ? 3 : 4)
                        .padding(.vertical, 2)
                        .background(Color.expense, in: Capsule())
                        .offset(x: 8, y: -6)
                }
            }
        }
        .accessibilityLabel(vm.unreadCount == 0 ? Text("Notifications") : Text("\(vm.unreadCount) unread notifications"))
        .sheet(isPresented: $showSheet) {
            NotificationsSheet(vm: vm)
        }
    }
}
