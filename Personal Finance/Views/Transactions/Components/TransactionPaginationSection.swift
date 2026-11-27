import SwiftUI

struct TransactionPaginationSection: View {
    let selectedDate: Date?
    let hasMore: Bool
    let isLoadingMore: Bool
    let loadedCount: Int
    let onLoadMore: () async -> Void

    var body: some View {
        if selectedDate == nil {
            if hasMore || isLoadingMore {
                Section {
                    HStack {
                        Spacer()
                        if isLoadingMore { ProgressView() } else { Color.clear.frame(height: 1) }
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                    .onAppear { Task { await onLoadMore() } }
                }
            } else if loadedCount > 0 {
                Section {
                    Text("All \(loadedCount) transactions loaded")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                }
            }
        }
    }
}
