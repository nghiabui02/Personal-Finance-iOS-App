import SwiftUI

struct TransactionListSection: View {
    let groups: [(Date, [LocalTransaction])]
    let isLoading: Bool
    let onTap: (LocalTransaction) -> Void
    let onDelete: (LocalTransaction) async -> Void

    var body: some View {
        if isLoading {
            Section {
                TransactionListSkeleton()
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color(.systemGroupedBackground))
            .listRowSeparator(.hidden)
        } else if groups.isEmpty {
            Section {
                ContentUnavailableView("No Transactions", systemImage: "tray",
                    description: Text("Tap + to add a transaction"))
                    .padding(.vertical, 16)
            }
            .listRowBackground(Color(.systemGroupedBackground))
            .listRowSeparator(.hidden)
        } else {
            ForEach(groups, id: \.0) { date, txs in
                Section {
                    ForEach(Array(txs.enumerated()), id: \.element.serverId) { idx, tx in
                        TransactionRow(transaction: tx, showDivider: idx < txs.count - 1)
                            .contentShape(Rectangle())
                            .onTapGesture { onTap(tx) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task { await onDelete(tx) }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                            .listRowBackground(
                                UnevenRoundedRectangle(
                                    topLeadingRadius:     idx == 0              ? 12 : 0,
                                    bottomLeadingRadius:  idx == txs.count - 1 ? 12 : 0,
                                    bottomTrailingRadius: idx == txs.count - 1 ? 12 : 0,
                                    topTrailingRadius:    idx == 0              ? 12 : 0
                                )
                                .fill(Color(.systemBackground))
                                .padding(.horizontal, 16)
                            )
                    }
                } header: {
                    sectionHeader(date: date, txs: txs)
                }
                .listSectionSeparator(.hidden)
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(date: Date, txs: [LocalTransaction]) -> some View {
        let net = txs.reduce(0.0) { $0 + ($1.type == "income" ? $1.amount : -$1.amount) }
        HStack {
            Text(sectionTitle(for: date))
                .font(.caption.weight(.semibold))
                .textCase(nil)
                .foregroundColor(.secondary)
            Spacer()
            if net != 0 {
                Text(netLabel(net))
                    .font(.caption)
                    .foregroundColor(net >= 0 ? .income : .expense)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func sectionTitle(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "TODAY" }
        if cal.isDateInYesterday(date) { return "YESTERDAY" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date).uppercased()
    }

    private func netLabel(_ net: Double) -> String {
        let abs = Swift.abs(net)
        return "\(net < 0 ? "-" : "")\(abs.formatted(currency: "VND"))"
    }
}
