import SwiftUI
import SwiftData

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalTransaction.transactionDate, order: .reverse) private var allTx: [LocalTransaction]
    @StateObject private var sync = SyncManager.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedMonth: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date()))!
    @State private var filterType: FilterType = .all
    @State private var showAdd = false
    @State private var editing: LocalTransaction?
    @State private var errorMsg: String?

    enum FilterType: String, CaseIterable {
        case all = "All"
        case income = "Income"
        case expense = "Expense"
    }

    private var filtered: [LocalTransaction] {
        allTx.filter { tx in
            Calendar.current.isDate(tx.transactionDate, equalTo: selectedMonth, toGranularity: .month)
            && (filterType == .all || tx.type == filterType.rawValue.lowercased())
        }
    }

    private var grouped: [(Date, [LocalTransaction])] {
        let cal = Calendar.current
        var dict: [Date: [LocalTransaction]] = [:]
        for tx in filtered {
            let day = cal.startOfDay(for: tx.transactionDate)
            dict[day, default: []].append(tx)
        }
        return dict.sorted { $0.key > $1.key }
    }

    private var totalIncome: Double  { filtered.filter { $0.type == "income"  }.reduce(0) { $0 + $1.amount } }
    private var totalExpense: Double { filtered.filter { $0.type == "expense" }.reduce(0) { $0 + $1.amount } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Month selector + summary
                VStack(spacing: 0) {
                    MonthSelectorView(selectedMonth: $selectedMonth)
                        .padding(.horizontal)

                    HStack(spacing: 0) {
                        summaryCell(label: "Income", amount: totalIncome, color: .income,
                                    icon: "arrow.down.circle.fill")
                        Divider().frame(height: 32)
                        summaryCell(label: "Expense", amount: totalExpense, color: .expense,
                                    icon: "arrow.up.circle.fill")
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                .background(Color(.systemBackground))

                // Filter tabs
                Picker("Filter", selection: $filterType) {
                    ForEach(FilterType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal).padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))

                Divider()

                if grouped.isEmpty {
                    ContentUnavailableView(
                        "No Transactions",
                        systemImage: "tray",
                        description: Text("Tap + to add a transaction")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(grouped, id: \.0) { date, txs in
                            Section {
                                ForEach(txs, id: \.serverId) { tx in
                                    TransactionRow(transaction: tx)
                                        .contentShape(Rectangle())
                                        .onTapGesture { editing = tx }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button(role: .destructive) {
                                                Task { await deleteTx(tx) }
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                            } header: {
                                Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                                    .textCase(nil)
                                    .font(.subheadline).fontWeight(.medium)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Transactions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .refreshable { await sync.syncAll(modelContext: modelContext) }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active { Task { await sync.syncAll(modelContext: modelContext) } }
            }
            .sheet(isPresented: $showAdd) {
                AddEditTransactionView(transaction: nil)
            }
            .sheet(item: $editing) { tx in
                AddEditTransactionView(transaction: tx)
            }
            .alert("Error", isPresented: Binding(
                get: { errorMsg != nil },
                set: { if !$0 { errorMsg = nil } }
            )) {
                Button("OK") { errorMsg = nil }
            } message: {
                Text(errorMsg ?? "")
            }
        }
    }

    @ViewBuilder
    private func summaryCell(label: String, amount: Double, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundColor(color).font(.subheadline)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundColor(.secondary)
                Text(amount.formatted(currency: "VND"))
                    .font(.subheadline).fontWeight(.semibold).foregroundColor(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private func deleteTx(_ tx: LocalTransaction) async {
        let wallets = (try? modelContext.fetch(FetchDescriptor<LocalWallet>())) ?? []
        let wallet = wallets.first { $0.serverId == tx.walletId }
        do {
            try await TransactionService.shared.delete(tx, wallet: wallet, in: modelContext)
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}

// MARK: - Transaction Row

struct TransactionRow: View {
    let transaction: LocalTransaction

    private var icon: String {
        if let i = transaction.categoryIcon, !i.isEmpty { return i }
        return transaction.type == "income" ? "💰" : "💸"
    }

    private var categoryOrType: String {
        transaction.categoryName ?? (transaction.type == "income" ? "Income" : "Expense")
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(.systemGray6))
                    .frame(width: 42, height: 42)
                Text(icon).font(.system(size: 20))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(categoryOrType)
                    .font(.subheadline).fontWeight(.medium).lineLimit(1)
                HStack(spacing: 4) {
                    if let note = transaction.note, !note.isEmpty {
                        Text(note).lineLimit(1)
                        Text("·")
                    }
                    Text(transaction.walletName)
                }
                .font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            Text("\(transaction.type == "income" ? "+" : "-")\(transaction.amount.formatted(currency: "VND"))")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundColor(transaction.type == "income" ? .income : .expense)
        }
        .padding(.vertical, 2)
    }
}
