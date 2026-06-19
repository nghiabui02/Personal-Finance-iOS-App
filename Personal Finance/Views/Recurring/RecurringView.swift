import SwiftUI
import SwiftData

struct RecurringView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalRecurringTransaction.amount, order: .reverse) private var recurring: [LocalRecurringTransaction]
    @Query(sort: \LocalWallet.name) private var wallets: [LocalWallet]

    @State private var showAdd = false
    @State private var editing: LocalRecurringTransaction?
    @State private var errorMsg: String?

    var body: some View {
        Group {
                if recurring.isEmpty {
                    ContentUnavailableView("No Recurring", systemImage: "arrow.clockwise.circle",
                        description: Text("Tap + to set up a recurring transaction"))
                } else {
                    List {
                        ForEach(recurring, id: \.serverId) { rec in
                            RecurringRow(rec: rec)
                                .onTapGesture { editing = rec }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        Task { await delete(rec) }
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Recurring")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { AddEditRecurringView(recurring: nil) }
            .sheet(item: $editing) { r in AddEditRecurringView(recurring: r) }
            .errorAlert($errorMsg)
    }

    private func delete(_ rec: LocalRecurringTransaction) async {
        do { try await RecurringService.shared.delete(rec, in: modelContext) }
        catch { errorMsg = error.localizedDescription }
    }
}

private struct RecurringRow: View {
    let rec: LocalRecurringTransaction

    private var freqLabel: String {
        switch rec.frequency {
        case "daily": return "Daily"
        case "weekly": return "Weekly"
        case "monthly": return "Monthly"
        case "yearly": return "Yearly"
        default: return rec.frequency.capitalized
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(rec.type == "income" ? Color.income.opacity(0.12) : Color.expense.opacity(0.12))
                    .frame(width: 44, height: 44)
                Text(rec.categoryIcon ?? (rec.type == "income" ? "💰" : "💸")).font(.system(size: 22))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(rec.categoryName ?? (rec.type == "income" ? "Income" : "Expense"))
                    .fontWeight(.medium)
                HStack(spacing: 4) {
                    Text(freqLabel)
                    if let next = rec.nextRunDate {
                        Text("·")
                        Text("Next: \(next.formatted(.dateTime.month(.abbreviated).day()))")
                    }
                }
                .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text("\(rec.type == "income" ? "+" : "-")\(rec.amount.formatted(currency: "VND"))")
                .fontWeight(.semibold)
                .foregroundColor(rec.type == "income" ? .income : .expense)
        }
        .padding(.vertical, 2)
    }
}
