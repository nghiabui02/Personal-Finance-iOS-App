import SwiftUI

struct TransactionPaginationSection: View {
    let selectedDate: Date?
    let hasMore: Bool
    let isLoadingMore: Bool
    let count: Int
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
            } else if count > 0 {
                Section {
                    Text("All \(count) transactions loaded")
                        .font(.caption).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                }
            }
        }
    }
}
