import SwiftUI

struct TransactionListSection: View {
    let groups: [(Date, [LocalTransaction])]
    let isLoading: Bool
    var isFiltered = false
    let onTap: (LocalTransaction) -> Void
    let onDeleteRequest: (LocalTransaction) -> Void

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
                ContentUnavailableView(
                    isFiltered ? "No Matching Transactions" : "No Transactions",
                    systemImage: isFiltered ? "line.3.horizontal.decrease.circle" : "tray",
                    description: Text(isFiltered ? "Try changing or clearing the filters" : "Tap + to add a transaction")
                )
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
                            .onTapGesture { if !tx.isTransfer { onTap(tx) } }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !tx.isTransfer {
                                    Button {
                                        onDeleteRequest(tx)
                                    } label: { Label("Delete", systemImage: "trash") }
                                    .tint(.red)
                                }
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                            .listRowBackground(
                                UnevenRoundedRectangle(
                                    topLeadingRadius: idx == 0              ? 12 : 0,
                                    bottomLeadingRadius: idx == txs.count - 1 ? 12 : 0,
                                    bottomTrailingRadius: idx == txs.count - 1 ? 12 : 0,
                                    topTrailingRadius: idx == 0              ? 12 : 0
                                )
                                .fill(Color(.secondarySystemGroupedBackground))
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
        let net = txs.reduce(0.0) { $0 + ($1.type == .income ? $1.amount : -$1.amount) }
        HStack {
            Text(sectionTitle(for: date))
                .font(.caption.weight(.semibold))
                .textCase(nil)
                .foregroundStyle(.secondary)
            Spacer()
            if net != 0 {
                Text(netLabel(net))
                    .font(.caption)
                    .foregroundStyle(net >= 0 ? Color.income : Color.expense)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func sectionTitle(for date: Date) -> String {
        let cal = LedgerDate.calendar
        let language = AppLocalization.shared.language
        let title: String
        if cal.isDateInToday(date) {
            title = language.text("Today")
        } else if cal.isDateInYesterday(date) {
            title = language.text("Yesterday")
        } else {
            title = date.formatted(LedgerDate.display(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
        }
        return title.uppercased(with: language.locale)
    }

    private func netLabel(_ net: Decimal) -> String {
        let abs = Swift.abs(net)
        return "\(net < 0 ? "-" : "")\(abs.formatted(currency: "VND"))"
    }
}
