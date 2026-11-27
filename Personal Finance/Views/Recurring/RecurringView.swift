import SwiftUI
import SwiftData

struct RecurringView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalRecurringTransaction.amount, order: .reverse) private var recurring: [LocalRecurringTransaction]
    @Query(sort: \LocalWallet.name) private var wallets: [LocalWallet]
    private var sync: SyncManager { .shared }

    @State private var showAdd = false
    @State private var editing: LocalRecurringTransaction?
    @State private var pendingDeletion: LocalRecurringTransaction?
    @State private var showDeleteConfirmation = false
    @State private var pendingSkip: LocalRecurringTransaction?
    @State private var showSkipConfirmation = false
    @State private var errorMsg: String?

    var body: some View {
        List {
                ForEach(recurring, id: \.serverId) { rec in
                    RecurringRow(rec: rec)
                        .onTapGesture { editing = rec }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                pendingDeletion = rec
                                showDeleteConfirmation = true
                            } label: { Label("Delete", systemImage: "trash") }
                            .tint(.red)

                            Button {
                                Task { await toggleActive(rec) }
                            } label: {
                                Label(rec.active ? "Pause" : "Resume", systemImage: rec.active ? "pause.circle" : "play.circle")
                            }
                            .tint(rec.active ? .orange : .green)

                            Button {
                                pendingSkip = rec
                                showSkipConfirmation = true
                            } label: {
                                Label("Skip", systemImage: "forward.end")
                            }
                            .tint(.blue)
                        }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await sync.syncAll(modelContext: modelContext) }
            .overlay {
                if recurring.isEmpty {
                    ContentUnavailableView("No Recurring", systemImage: "arrow.clockwise.circle",
                        description: Text("Tap + to set up a recurring transaction"))
                }
            }
            .navigationTitle("Recurring")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { AddEditRecurringView(recurring: nil) }
            .sheet(item: $editing) { r in AddEditRecurringView(recurring: r) }
            .deleteConfirmation(
                item: $pendingDeletion,
                isPresented: $showDeleteConfirmation,
                title: "Delete Recurring Transaction?",
                message: "The recurring rule will be permanently deleted."
            ) { recurring in
                Task { await delete(recurring) }
            }
            // A skipped occurrence is never recorded and cannot be undone, so a stray swipe must not do it.
            .deleteConfirmation(
                item: $pendingSkip,
                isPresented: $showSkipConfirmation,
                title: "Skip Next Occurrence?",
                message: "The next transaction from this rule will not be recorded.",
                confirmLabel: "Skip"
            ) { recurring in
                Task { await skip(recurring) }
            }
            .errorAlert($errorMsg)
    }

    private func delete(_ rec: LocalRecurringTransaction) async {
        do {
            try await RecurringService.shared.delete(rec, in: modelContext)
        } catch {
            errorMsg = error.asDisplayableError().localizedDescription
        }
    }

    private func toggleActive(_ rec: LocalRecurringTransaction) async {
        do {
            try await RecurringService.shared.toggleActive(rec, in: modelContext)
        } catch {
            errorMsg = error.asDisplayableError().localizedDescription
        }
    }

    private func skip(_ rec: LocalRecurringTransaction) async {
        do {
            try await RecurringService.shared.skip(rec, in: modelContext)
        } catch {
            errorMsg = error.asDisplayableError().localizedDescription
        }
    }
}

private struct RecurringRow: View {
    let rec: LocalRecurringTransaction

    private var freqLabel: LocalizedStringKey {
        switch rec.frequency {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(rec.type == .income ? Color.income.opacity(0.12) : Color.expense.opacity(0.12))
                    .frame(width: 44, height: 44)
                Text(rec.categoryIcon ?? (rec.type == .income ? "💰" : "💸")).font(.system(size: 22))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(rec.categoryLabel ?? AppLocalization.shared.language.text(rec.type == .income ? "Income" : "Expense"))
                    .fontWeight(.medium)
                HStack(spacing: 4) {
                    Text(freqLabel)
                    if let next = rec.nextRunDate {
                        Text("·")
                        Text("Next: \(next.formatted(LedgerDate.display(.dateTime.month(.abbreviated).day())))")
                    }
                    if rec.bankFee > 0 {
                        Text("·")
                        Text("+ \(rec.bankFee.formatted(currency: "VND")) fee")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(rec.type == .income ? "+" : "-")\(rec.amount.formatted(currency: "VND"))")
                    .fontWeight(.semibold)
                    .foregroundStyle(rec.type == .income ? Color.income : Color.expense)
                if !rec.active {
                    Text("Paused")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 2)
    }
}
