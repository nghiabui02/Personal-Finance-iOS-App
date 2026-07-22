import SwiftUI

struct DebtsContentView: View {
    @Binding var filterType: DebtFilterType

    let activeDebts: [LocalDebt]
    let completedDebts: [LocalDebt]
    let isEmpty: Bool
    let onPay: (LocalDebt) -> Void
    let onAdd: (LocalDebt) -> Void
    let onDelete: (LocalDebt) -> Void
    let onRefresh: () async -> Void

    var body: some View {
        VStack(spacing: 0) {
            DebtFilterPicker(filterType: $filterType)

            List {
                if !activeDebts.isEmpty {
                    activeSection
                }

                if !completedDebts.isEmpty {
                    completedSection
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await onRefresh() }
            .overlay {
                if isEmpty {
                    ContentUnavailableView(
                        "No Debts",
                        systemImage: "dollarsign.circle",
                        description: Text("Tap + to add a debt record")
                    )
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private var activeSection: some View {
        Section("Active") {
            ForEach(activeDebts, id: \.serverId) { debt in
                NavigationLink {
                    DebtDetailView(debt: debt)
                } label: {
                    DebtRow(debt: debt, onPay: { onPay(debt) }, onAdd: { onAdd(debt) })
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        onPay(debt)
                    } label: {
                        Label("Pay", systemImage: "checkmark.circle")
                    }
                    .tint(.green)

                    Button {
                        onAdd(debt)
                    } label: {
                        Label("Add", systemImage: "plus.circle")
                    }
                    .tint(.orange)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        onDelete(debt)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
        }
    }

    private var completedSection: some View {
        Section("Completed") {
            ForEach(completedDebts, id: \.serverId) { debt in
                NavigationLink {
                    DebtDetailView(debt: debt)
                } label: {
                    DebtRow(debt: debt)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct DebtFilterPicker: View {
    @Binding var filterType: DebtFilterType

    var body: some View {
        Picker("Filter", selection: $filterType) {
            ForEach(DebtFilterType.allCases) { filter in
                Text(filter.rawValue)
                    .tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .tint(filterType.tintColor)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }
}
