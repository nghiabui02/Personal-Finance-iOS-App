import SwiftUI
import SwiftData
import Supabase

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var sync = SyncManager.shared
    @Environment(\.scenePhase) private var scenePhase

    // Paginated state
    @State private var loadedTxs: [LocalTransaction] = []
    @State private var serverPage = 0
    @State private var isLoadingMore = false
    @State private var hasMore = true
    @State private var loadedIds: Set<UUID> = []

    // Period totals (full period, not just loaded pages)
    @State private var periodIncome:  Double = 0
    @State private var periodExpense: Double = 0

    // Daily data for calendar annotations
    @State private var dailyData: [Date: (income: Double, expense: Double)] = [:]

    // Grouped cache — recomputed only when loadedTxs changes
    @State private var groupedAll:     [(Date, [LocalTransaction])] = []
    @State private var groupedIncome:  [(Date, [LocalTransaction])] = []
    @State private var groupedExpense: [(Date, [LocalTransaction])] = []

    @State private var selectedMonth: Date = {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
    }()
    @State private var selectedDate: Date? = nil
    @State private var filterType: FilterType = .all
    @State private var showAdd = false
    @State private var editing: LocalTransaction?
    @State private var errorMsg: String?
    @State private var isLoadingDateTxs = false

    private let pageSize = 10
    private let client = SupabaseService.shared.client
    private let df: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    enum FilterType: String, CaseIterable { case all = "All", income = "Income", expense = "Expense" }

    private var currentMonthStart: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
    }

    private var isOnCurrentMonth: Bool {
        Calendar.current.isDate(selectedMonth, equalTo: Date(), toGranularity: .month)
    }

    // MARK: - Computed

    private var displayedIncome: Double {
        guard let date = selectedDate else { return periodIncome }
        return dailyData[Calendar.current.startOfDay(for: date)]?.income ?? 0
    }

    private var displayedExpense: Double {
        guard let date = selectedDate else { return periodExpense }
        return dailyData[Calendar.current.startOfDay(for: date)]?.expense ?? 0
    }

    private func displayedGroups(for type: FilterType) -> [(Date, [LocalTransaction])] {
        let base = cachedGroups(for: type)
        guard let date = selectedDate else { return base }
        return base.filter { Calendar.current.isDate($0.0, inSameDayAs: date) }
    }

    private func cachedGroups(for type: FilterType) -> [(Date, [LocalTransaction])] {
        switch type {
        case .all:     return groupedAll
        case .income:  return groupedIncome
        case .expense: return groupedExpense
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                calendarHeaderSection
                transactionSections
                paginationSection
            }
            .listStyle(.grouped)
            .listSectionSpacing(8)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Transactions")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !isOnCurrentMonth {
                        Button("Today") { jumpToToday() }
                            .font(.subheadline)
                            .transition(.opacity)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isOnCurrentMonth)
            .refreshable { resetAndLoad() }
            .onChange(of: scenePhase)    { _, p in if p == .active { resetAndLoad() } }
            .onChange(of: selectedMonth) { _, _ in resetAndLoad() }
            .onChange(of: loadedTxs)    { _, _ in recomputeGrouped() }
            .onChange(of: selectedDate) { _, date in
                guard let date else { return }
                Task { await ensureDateLoaded(date) }
            }
            .onAppear {
                let current = currentMonthStart
                if selectedMonth != current {
                    // Tab switched away and back — reset to current month
                    selectedMonth = current   // triggers onChange → resetAndLoad()
                } else if loadedTxs.isEmpty {
                    resetAndLoad()
                }
            }
            .sheet(isPresented: $showAdd) {
                AddEditTransactionView(transaction: nil, defaultDate: selectedDate)
            }
            .sheet(item: $editing) { tx in AddEditTransactionView(transaction: tx) }
            .alert("Error", isPresented: Binding(
                get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } }
            )) { Button("OK") { errorMsg = nil } } message: { Text(errorMsg ?? "") }
        }
    }

    // MARK: - List sections

    @ViewBuilder
    private var calendarHeaderSection: some View {
        Section {
            VStack(spacing: 10) {
                MonthCalendarView(
                    selectedMonth: $selectedMonth,
                    selectedDate: $selectedDate,
                    dailyData: dailyData
                )

                HStack(spacing: 8) {
                    TxStatBox(label: "Income",  amount: displayedIncome,  color: .income)
                    TxStatBox(label: "Expense", amount: displayedExpense, color: .expense)
                    let net = displayedIncome - displayedExpense
                    TxStatBox(label: "Net", amount: net, color: net >= 0 ? .income : .expense)
                }

                Picker("Filter", selection: $filterType) {
                    ForEach(FilterType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 30).onEnded { v in
                        let h = v.translation.width; let vert = v.translation.height
                        guard abs(h) > abs(vert) * 1.5, abs(h) > 40 else { return }
                        withAnimation(.easeInOut(duration: 0.2)) { cycleFilter(by: h < 0 ? 1 : -1) }
                    }
                )
            }
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowBackground(Color(.systemGroupedBackground))
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var transactionSections: some View {
        if loadedTxs.isEmpty && (isLoadingMore || isLoadingDateTxs) {
            Section {
                TransactionListSkeleton()
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color(.systemGroupedBackground))
            .listRowSeparator(.hidden)
        } else {
            let groups = displayedGroups(for: filterType)
            if groups.isEmpty && !isLoadingMore {
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
                                .onTapGesture { editing = tx }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        Task { await deleteTx(tx) }
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
                                .listRowBackground(
                                    UnevenRoundedRectangle(
                                        topLeadingRadius:    idx == 0              ? 12 : 0,
                                        bottomLeadingRadius: idx == txs.count - 1 ? 12 : 0,
                                        bottomTrailingRadius: idx == txs.count - 1 ? 12 : 0,
                                        topTrailingRadius:   idx == 0              ? 12 : 0
                                    )
                                    .fill(Color(.systemBackground))
                                    .padding(.horizontal, 16)
                                )
                        }
                    } header: {
                        txSectionHeader(date: date, txs: txs)
                    }
                    .listSectionSeparator(.hidden)
                }
            }
        }
    }

    @ViewBuilder
    private var paginationSection: some View {
        if selectedDate == nil {
            if hasMore || isLoadingMore {
                Section {
                    HStack {
                        Spacer()
                        if isLoadingMore { ProgressView() } else { Color.clear.frame(height: 1) }
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                    .onAppear { Task { await loadMore() } }
                }
            } else if !loadedTxs.isEmpty {
                Section {
                    Text("All \(loadedTxs.count) transactions loaded")
                        .font(.caption).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                }
            }
        }
    }

    // MARK: - Section header

    @ViewBuilder
    private func txSectionHeader(date: Date, txs: [LocalTransaction]) -> some View {
        let net = txs.reduce(0.0) { $0 + ($1.type == "income" ? $1.amount : -$1.amount) }
        HStack {
            Text(sectionTitle(for: date))
                .font(.caption.weight(.semibold))
                .textCase(nil)
                .foregroundColor(.secondary)
            Spacer()
            if net != 0 {
                Text(netString(net))
                    .font(.caption)
                    .foregroundColor(net >= 0 ? .income : .expense)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func sectionTitle(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "TODAY" }
        if cal.isDateInYesterday(date) { return "YESTERDAY" }
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date).uppercased()
    }

    private func netString(_ net: Double) -> String {
        let abs = Swift.abs(net)
        return "\(net < 0 ? "-" : "")\(abs.formatted(currency: "VND"))"
    }

    // MARK: - Grouped cache

    private func recomputeGrouped() {
        let cal = Calendar.current
        var all: [Date: [LocalTransaction]] = [:]
        var inc: [Date: [LocalTransaction]] = [:]
        var exp: [Date: [LocalTransaction]] = [:]
        for tx in loadedTxs {
            let day = cal.startOfDay(for: tx.transactionDate)
            all[day, default: []].append(tx)
            if tx.type == "income" { inc[day, default: []].append(tx) }
            else                   { exp[day, default: []].append(tx) }
        }
        groupedAll     = all.sorted { $0.key > $1.key }
        groupedIncome  = inc.sorted { $0.key > $1.key }
        groupedExpense = exp.sorted { $0.key > $1.key }
    }

    // MARK: - Load & pagination

    private func resetAndLoad() {
        loadedTxs = []; loadedIds = []
        groupedAll = []; groupedIncome = []; groupedExpense = []
        periodIncome = 0; periodExpense = 0
        dailyData = [:]; selectedDate = nil
        serverPage = 0; hasMore = true
        Task { await fetchPeriodTotals() }
        Task { await loadMore() }
    }

    private func fetchPeriodTotals() async {
        let (startStr, endStr) = periodRange()
        struct TotalRecord: Decodable {
            let type: String; let amount: Double; let transaction_date: String
        }
        do {
            let userId = try await client.auth.session.user.id
            let records: [TotalRecord] = try await client
                .from("transactions")
                .select("type,amount,transaction_date")
                .eq("user_id", value: userId)
                .gte("transaction_date", value: startStr)
                .lt("transaction_date",  value: endStr)
                .execute().value

            var inc = 0.0, exp = 0.0
            var daily: [Date: (income: Double, expense: Double)] = [:]
            let cal = Calendar.current
            for r in records {
                if r.type == "income" { inc += r.amount } else { exp += r.amount }
                if let date = df.date(from: r.transaction_date) {
                    let day = cal.startOfDay(for: date)
                    var d = daily[day] ?? (income: 0, expense: 0)
                    if r.type == "income" { d.income += r.amount } else { d.expense += r.amount }
                    daily[day] = d
                }
            }
            periodIncome = inc; periodExpense = exp; dailyData = daily
        } catch {
            guard let start = df.date(from: startStr), let end = df.date(from: endStr) else { return }
            let desc = FetchDescriptor<LocalTransaction>(
                predicate: #Predicate<LocalTransaction> { $0.transactionDate >= start && $0.transactionDate < end }
            )
            let local = (try? modelContext.fetch(desc)) ?? []
            periodIncome  = local.filter { $0.type == "income"  }.reduce(0) { $0 + $1.amount }
            periodExpense = local.filter { $0.type == "expense" }.reduce(0) { $0 + $1.amount }
            var daily: [Date: (income: Double, expense: Double)] = [:]
            let cal = Calendar.current
            for tx in local {
                let day = cal.startOfDay(for: tx.transactionDate)
                var d = daily[day] ?? (income: 0, expense: 0)
                if tx.type == "income" { d.income += tx.amount } else { d.expense += tx.amount }
                daily[day] = d
            }
            dailyData = daily
        }
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
            if loadedTxs.isEmpty { fallbackFromCache() }
            hasMore = false
            if sync.isOnline { errorMsg = error.localizedDescription }
        }
    }

    // Load all transactions for a specific selected date
    private func ensureDateLoaded(_ date: Date) async {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return }

        // Skip if already loaded
        let alreadyHaveData = loadedTxs.contains { $0.transactionDate >= start && $0.transactionDate < end }
        let dayHasData = (dailyData[start]?.income ?? 0) + (dailyData[start]?.expense ?? 0) > 0
        guard !alreadyHaveData && dayHasData else { return }

        isLoadingDateTxs = true
        defer { isLoadingDateTxs = false }

        let startStr = df.string(from: start)
        let endStr   = df.string(from: end)

        do {
            let userId = try await client.auth.session.user.id
            let remote: [RemoteTransaction] = try await client
                .from("transactions")
                .select("*, categories(id, name, icon, color), wallets(id, name)")
                .eq("user_id", value: userId)
                .gte("transaction_date", value: startStr)
                .lt("transaction_date",  value: endStr)
                .order("transaction_date", ascending: false)
                .execute().value
            upsert(remote)
        } catch {
            // Fallback: load from local SwiftData for that day
            let desc = FetchDescriptor<LocalTransaction>(
                predicate: #Predicate<LocalTransaction> { $0.transactionDate >= start && $0.transactionDate < end },
                sortBy: [SortDescriptor(\.transactionDate, order: .reverse)]
            )
            let local = (try? modelContext.fetch(desc)) ?? []
            for tx in local where !loadedIds.contains(tx.serverId) {
                loadedTxs.append(tx); loadedIds.insert(tx.serverId)
            }
        }
    }

    private func upsert(_ remotes: [RemoteTransaction]) {
        guard !remotes.isEmpty else { return }
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
                if !loadedIds.contains(r.id) { loadedTxs.append(local); loadedIds.insert(r.id) }
            } else {
                let local = LocalTransaction(from: r)
                modelContext.insert(local)
                loadedTxs.append(local); loadedIds.insert(r.id)
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

    private func jumpToToday() {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedDate = nil
            selectedMonth = currentMonthStart  // triggers onChange → resetAndLoad()
        }
    }

    private func periodRange() -> (String, String) {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: selectedMonth)
        let start = cal.date(from: comps)!
        let end   = cal.date(byAdding: .month, value: 1, to: start)!
        return (df.string(from: start), df.string(from: end))
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
            Task { await fetchPeriodTotals() }
        } catch { errorMsg = error.localizedDescription }
    }
}

// MARK: - Month Calendar View

struct MonthCalendarView: View {
    @Binding var selectedMonth: Date
    @Binding var selectedDate: Date?
    let dailyData: [Date: (income: Double, expense: Double)]

    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdaySymbols = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private var firstDayOfMonth: Date {
        cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth))!
    }

    private var daysInMonth: Int {
        cal.range(of: .day, in: .month, for: selectedMonth)!.count
    }

    // Offset so week starts on Monday (Sun=1→6, Mon=2→0, ..., Sat=7→5)
    private var startOffset: Int {
        let weekday = cal.component(.weekday, from: firstDayOfMonth)
        return (weekday - 2 + 7) % 7
    }

    private var today: Date { cal.startOfDay(for: Date()) }

    // Disable "next" when selectedMonth is the current month or in the future
    private var nextDisabled: Bool {
        let current = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        return selectedMonth >= current
    }

    // Single flat array avoids ID conflicts between the two ForEach ranges
    private struct GridCell: Identifiable {
        let id: String
        let day: Int?
        let date: Date?
    }

    private var gridCells: [GridCell] {
        var cells: [GridCell] = (0..<startOffset).map { GridCell(id: "e\($0)", day: nil, date: nil) }
        for day in 1...daysInMonth {
            let date = cal.date(byAdding: .day, value: day - 1, to: firstDayOfMonth)!
            cells.append(GridCell(id: "d\(day)", day: day, date: date))
        }
        return cells
    }

    var body: some View {
        VStack(spacing: 0) {
            // Month navigation — use onTapGesture so taps aren't swallowed by List row
            HStack {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture { changeMonth(by: -1) }

                Spacer()
                Text(selectedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline.weight(.bold))
                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(nextDisabled ? Color.secondary.opacity(0.25) : .secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture { if !nextDisabled { changeMonth(by: 1) } }
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Weekday header
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { sym in
                    Text(sym)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)

            // Day grid — single array ensures unique IDs across empty + day cells
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(gridCells) { cell in
                    if let day = cell.day, let date = cell.date {
                        let isToday    = date == today
                        let isSelected = selectedDate.map { cal.isDate($0, inSameDayAs: date) } ?? false
                        CalendarDayCell(
                            day: day, date: date,
                            isToday: isToday, isSelected: isSelected,
                            data: dailyData[date]
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedDate = isSelected ? nil : date
                            }
                        }
                    } else {
                        Color.clear.frame(height: 46)
                    }
                }
            }
            .padding(.bottom, 10)
        }
        .background(Color(.systemBackground))
        .cornerRadius(14)
    }

    private func changeMonth(by delta: Int) {
        if let next = cal.date(byAdding: .month, value: delta, to: selectedMonth) {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedMonth = next
                selectedDate = nil
            }
        }
    }
}

private struct CalendarDayCell: View {
    let day: Int
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let data: (income: Double, expense: Double)?
    let onTap: () -> Void

    private var net: Double? {
        guard let d = data else { return nil }
        let n = d.income - d.expense
        return n == 0 ? nil : n
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 1) {
                ZStack {
                    if isSelected {
                        Circle().fill(Color.primary).frame(width: 30, height: 30)
                    } else if isToday {
                        Circle().fill(Color.blue).frame(width: 30, height: 30)
                    }
                    Text("\(day)")
                        .font(.subheadline)
                        .foregroundColor(isSelected || isToday ? .white : .primary)
                }
                .frame(height: 30)

                if let n = net {
                    Text(compactNet(n))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(n > 0 ? .income : .expense)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else {
                    Color.clear.frame(height: 11)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func compactNet(_ n: Double) -> String {
        let abs = Swift.abs(n)
        let sign = n > 0 ? "+" : "-"
        if abs >= 1_000_000_000 {
            return "\(sign)\(String(format: "%.1f", abs / 1_000_000_000))B"
        } else if abs >= 1_000_000 {
            return "\(sign)\(Int(abs / 1_000_000))M"
        } else if abs >= 1_000 {
            return "\(sign)\(Int(abs / 1_000))k"
        }
        return "\(sign)\(Int(abs))"
    }
}

// MARK: - Stat Box

private struct TxStatBox: View {
    let label: String
    let amount: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(amount.formatted(currency: "VND"))
                .font(.caption.weight(.bold))
                .foregroundColor(color)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(color.opacity(0.08))
        .cornerRadius(10)
    }
}

// MARK: - Transaction Row

struct TransactionRow: View {
    let transaction: LocalTransaction
    var showDivider: Bool = false

    private var icon: String {
        if let i = transaction.categoryIcon, !i.isEmpty { return i }
        return transaction.type == "income" ? "💰" : "💸"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(.systemGray6)).frame(width: 44, height: 44)
                    Text(icon).font(.system(size: 22))
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
            .padding(.vertical, 8)

            if showDivider {
                Divider().padding(.leading, 56)
            }
        }
    }
}

// MARK: - Week Selector (kept for potential future use)

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
