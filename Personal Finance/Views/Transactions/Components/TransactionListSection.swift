import SwiftUI

struct TransactionListSection: View {
    let groups: [(Date, [LocalTransaction])]
    /// Whole-day operating totals, the same ones the calendar shows. Summing the visible rows
    /// instead would count loans and transfers, and only part of a day cut by pagination.
    let dailyTotals: DailyTotals
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
                    sectionHeader(date: date)
                }
                .listSectionSeparator(.hidden)
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(date: Date) -> some View {
        let totals = dailyTotals[date]
        let net = (totals?.income ?? 0) - (totals?.expense ?? 0)
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
