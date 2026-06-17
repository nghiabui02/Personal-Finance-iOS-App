import SwiftUI
import SwiftData
import Supabase

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var sync = SyncManager.shared
    @Environment(\.scenePhase) private var scenePhase

    // Paginated state — not @Query (load on demand)
    @State private var loadedTxs: [LocalTransaction] = []
    @State private var serverPage = 0
    @State private var isLoadingMore = false
    @State private var hasMore = true
    @State private var loadedIds: Set<UUID> = []   // O(1) duplicate check

    @State private var periodMode: PeriodMode = .month
    @State private var selectedMonth: Date = {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
    }()
    @State private var selectedWeekStart: Date = Self.weekStart(from: Date())
    @State private var filterType: FilterType = .all
    @State private var showAdd = false
    @State private var editing: LocalTransaction?
    @State private var errorMsg: String?

    private let pageSize = 10
    private let client = SupabaseService.shared.client
    private let df: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    enum PeriodMode: String, CaseIterable { case month = "Month", week = "Week" }
    enum FilterType: String, CaseIterable { case all = "All", income = "Income", expense = "Expense" }

    // MARK: - Computed

    private func filtered(for type: FilterType) -> [LocalTransaction] {
        type == .all ? loadedTxs : loadedTxs.filter { $0.type == type.rawValue.lowercased() }
    }

    private func grouped(for type: FilterType) -> [(Date, [LocalTransaction])] {
        let cal = Calendar.current
        var dict: [Date: [LocalTransaction]] = [:]
        for tx in filtered(for: type) {
            dict[cal.startOfDay(for: tx.transactionDate), default: []].append(tx)
        }
        return dict.sorted { $0.key > $1.key }
    }

    private var totalIncome:  Double { loadedTxs.filter { $0.type == "income"  }.reduce(0) { $0 + $1.amount } }
    private var totalExpense: Double { loadedTxs.filter { $0.type == "expense" }.reduce(0) { $0 + $1.amount } }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerSection

                filterPickerSection

                Divider()

                contentSection
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Transactions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .refreshable { resetAndLoad() }
            .onChange(of: scenePhase) { _, p in if p == .active { resetAndLoad() } }
            .onChange(of: periodMode)        { _, _ in resetAndLoad() }
            .onChange(of: selectedMonth)     { _, _ in if periodMode == .month { resetAndLoad() } }
            .onChange(of: selectedWeekStart) { _, _ in if periodMode == .week  { resetAndLoad() } }
            .onAppear { if loadedTxs.isEmpty { resetAndLoad() } }
            .sheet(isPresented: $showAdd)  { AddEditTransactionView(transaction: nil) }
            .sheet(item: $editing) { tx in  AddEditTransactionView(transaction: tx) }
            .alert("Error", isPresented: Binding(
                get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } }
            )) { Button("OK") { errorMsg = nil } } message: { Text(errorMsg ?? "") }
        }
    }

    // MARK: - Sub-sections (extracted to help type-checker)

    @ViewBuilder
    private var filterPickerSection: some View {
        Picker("Filter", selection: $filterType) {
            ForEach(FilterType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .tint(filterType == .income ? .income : filterType == .expense ? .expense : .blue)
        .padding(.horizontal).padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let h = value.translation.width
                    let v = value.translation.height
                    guard abs(h) > abs(v) * 1.5, abs(h) > 40 else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        cycleFilter(by: h < 0 ? 1 : -1)
                    }
                }
        )
    }

    @ViewBuilder
    private var contentSection: some View {
        if loadedTxs.isEmpty && isLoadingMore {
            TransactionListSkeleton()
        } else {
            transactionList(for: filterType)
        }
    }

    // MARK: - Per-tab list

    @ViewBuilder
    private func transactionList(for type: FilterType) -> some View {
        let groups = grouped(for: type)
        if groups.isEmpty && !isLoadingMore {
            ContentUnavailableView("No Transactions", systemImage: "tray",
                description: Text("Tap + to add a transaction"))
        } else {
            List {
                ForEach(groups, id: \.0) { date, txs in
                    Section {
                        ForEach(txs, id: \.serverId) { tx in
                            TransactionRow(transaction: tx)
                                .contentShape(Rectangle())
                                .onTapGesture { editing = tx }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        Task { await deleteTx(tx) }
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    } header: {
                        Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .textCase(nil).font(.subheadline).fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                }

                // Pagination trigger
                if hasMore || isLoadingMore {
                    HStack {
                        Spacer()
                        if isLoadingMore { ProgressView() } else { Color.clear.frame(height: 1) }
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                    .onAppear { Task { await loadMore() } }
                } else if !loadedTxs.isEmpty {
                    Text("All \(loadedTxs.count) transactions loaded")
                        .font(.caption).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity).listRowSeparator(.hidden)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 0) {
            Picker("Period", selection: $periodMode) {
                ForEach(PeriodMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 8)

            if periodMode == .month {
                MonthSelectorView(selectedMonth: $selectedMonth).padding(.horizontal)
            } else {
                WeekSelectorView(weekStart: $selectedWeekStart).padding(.horizontal)
            }

            HStack(spacing: 0) {
                summaryCell(label: "Income",  amount: totalIncome,  color: .income,  icon: "arrow.down.circle.fill")
                Divider().frame(height: 32)
                summaryCell(label: "Expense", amount: totalExpense, color: .expense, icon: "arrow.up.circle.fill")
            }
            .padding(.horizontal).padding(.bottom, 8)
        }
        .background(Color(.systemBackground))
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
        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
    }

    // MARK: - Pagination

    private func resetAndLoad() {
        loadedTxs = []
        loadedIds = []
        serverPage = 0
        hasMore = true
        Task { await loadMore() }
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore, sync.isOnline else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let (startStr, endStr) = periodRange()
        let from = serverPage * pageSize
        let to   = from + pageSize - 1

        do {
            let userId = try await client.auth.session.user.id
            let remote: [RemoteTransaction] = try await client
                .from("transactions")
                .select("*, categories(id, name, icon, color), wallets(id, name)")
                .eq("user_id", value: userId)
                .gte("transaction_date", value: startStr)
                .lt("transaction_date",  value: endStr)
                .order("transaction_date", ascending: false)
                .range(from: from, to: to)
                .execute().value

            upsert(remote)
            serverPage += 1
            if remote.count < pageSize { hasMore = false }
        } catch {
            // Offline: fall back to SwiftData cache for this period
            if loadedTxs.isEmpty { fallbackFromCache() }
            hasMore = false
            if sync.isOnline { errorMsg = error.localizedDescription }
        }
    }

    private func upsert(_ remotes: [RemoteTransaction]) {
        guard !remotes.isEmpty else { return }
        // Scope fetch to current period window — avoids loading full transaction history
        let (startStr, endStr) = periodRange()
        guard let start = df.date(from: startStr), let end = df.date(from: endStr) else { return }
        let desc = FetchDescriptor<LocalTransaction>(
            predicate: #Predicate<LocalTransaction> { $0.transactionDate >= start && $0.transactionDate < end }
        )
        let existing = (try? modelContext.fetch(desc)) ?? []
        let localMap = Dictionary(uniqueKeysWithValues: existing.map { ($0.serverId, $0) })

        for r in remotes {
            if let local = localMap[r.id] {
                local.update(from: r)
                if !loadedIds.contains(r.id) {
                    loadedTxs.append(local)
                    loadedIds.insert(r.id)
                }
            } else {
                let local = LocalTransaction(from: r)
                modelContext.insert(local)
                loadedTxs.append(local)
                loadedIds.insert(r.id)
            }
        }
        try? modelContext.save()
    }

    private func fallbackFromCache() {
        let (startStr, endStr) = periodRange()
        guard let start = df.date(from: startStr), let end = df.date(from: endStr) else { return }
        let all = (try? modelContext.fetch(
            FetchDescriptor<LocalTransaction>(sortBy: [SortDescriptor(\.transactionDate, order: .reverse)])
        )) ?? []
        loadedTxs = all.filter { $0.transactionDate >= start && $0.transactionDate < end }
    }

    // MARK: - Helpers

    private func periodRange() -> (String, String) {
        let cal = Calendar.current
        switch periodMode {
        case .month:
            let comps = cal.dateComponents([.year, .month], from: selectedMonth)
            let start = cal.date(from: comps)!
            let end   = cal.date(byAdding: .month, value: 1, to: start)!
            return (df.string(from: start), df.string(from: end))
        case .week:
            let end = cal.date(byAdding: .day, value: 7, to: selectedWeekStart)!
            return (df.string(from: selectedWeekStart), df.string(from: end))
        }
    }

    private func cycleFilter(by delta: Int) {
        let cases = FilterType.allCases
        guard let idx = cases.firstIndex(of: filterType) else { return }
        filterType = cases[(idx + delta + cases.count) % cases.count]
    }

    private func deleteTx(_ tx: LocalTransaction) async {
        let wallets = (try? modelContext.fetch(FetchDescriptor<LocalWallet>())) ?? []
        let wallet = wallets.first { $0.serverId == tx.walletId }
        do {
            try await TransactionService.shared.delete(tx, wallet: wallet, in: modelContext)
            loadedTxs.removeAll { $0.serverId == tx.serverId }
        } catch { errorMsg = error.localizedDescription }
    }

    private static func weekStart(from date: Date) -> Date {
        var cal = Calendar.current; cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: comps) ?? cal.startOfDay(for: date)
    }
}

// MARK: - Week Selector

struct WeekSelectorView: View {
    @Binding var weekStart: Date

    private var cal: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }
    private var weekEnd: Date { cal.date(byAdding: .day, value: 6, to: weekStart)! }

    private var isCurrentWeek: Bool {
        cal.isDate(weekStart, equalTo: Date(), toGranularity: .weekOfYear)
    }

    private var label: String {
        let s = weekStart.formatted(.dateTime.day().month(.abbreviated))
        let e = weekEnd.formatted(.dateTime.day().month(.abbreviated).year())
        return "\(s) – \(e)"
    }

    var body: some View {
        HStack(spacing: 16) {
            Button { change(by: -1) } label: {
                Image(systemName: "chevron.left").fontWeight(.semibold).foregroundColor(.primary)
            }
            Text(label).font(.headline).frame(minWidth: 180)
                .onTapGesture {
                    var c = Calendar.current; c.firstWeekday = 2
                    let comps = c.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
                    withAnimation { weekStart = c.date(from: comps) ?? Date() }
                }
            Button { change(by: 1) } label: {
                Image(systemName: "chevron.right").fontWeight(.semibold)
                    .foregroundColor(isCurrentWeek ? .secondary : .primary)
            }
            .disabled(isCurrentWeek)
        }
        .padding(.vertical, 8)
    }

    private func change(by weeks: Int) {
        if let next = cal.date(byAdding: .weekOfYear, value: weeks, to: weekStart) {
            withAnimation { weekStart = next }
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

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(.systemGray6)).frame(width: 42, height: 42)
                Text(icon).font(.system(size: 20))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.categoryName ?? (transaction.type == "income" ? "Income" : "Expense"))
                    .font(.subheadline).fontWeight(.medium).lineLimit(1)
                HStack(spacing: 4) {
                    if let note = transaction.note, !note.isEmpty { Text(note).lineLimit(1); Text("·") }
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
