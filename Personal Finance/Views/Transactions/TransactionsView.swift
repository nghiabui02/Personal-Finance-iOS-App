import SwiftUI
import SwiftData

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalCategory.name) private var categories: [LocalCategory]
    private var sync: SyncManager { .shared }
    @State private var selectedMonth = TransactionDateRange.monthStart(for: Date())
    @State private var visibleCount = Self.pageSize
    @State private var errorMessage: String?

    private static let pageSize = 30

    // UI-only state — does not drive data fetching
    @State private var selectedDate: Date? = Date()
    @State private var filter = TransactionFilterState()
    @State private var showAdd = false
    @State private var editing: LocalTransaction?
    @State private var pendingDeletion: LocalTransaction?
    @State private var showDeleteConfirmation = false

    private var monthWindow: Range<Date> {
        TransactionDateRange.window(endingWith: selectedMonth, monthsBefore: 0)
    }

    private var usesPagination: Bool { filter.period == .month && !filter.hasContentFilter }

    private func displayedGroups(_ monthTransactions: [LocalTransaction]) -> [(Date, [LocalTransaction])] {
        let rows = TransactionFilterEngine.apply(filter, to: monthTransactions, selectedMonth: selectedMonth,
                                                 selectedDate: selectedDate)
        return TransactionGroupingCalculator.group(usesPagination ? Array(rows.prefix(visibleCount)) : rows).all
    }

    private func headerSection(_ monthTransactions: [LocalTransaction]) -> some View {
        let dailyTotals = TransactionPeriodTotalsCalculator.dailyTotals(
            from: monthTransactions.operatingOnly(using: categories)
        )
        let interval = TransactionFilterEngine.dateInterval(for: filter.period, selectedMonth: selectedMonth,
                                                            selectedDate: selectedDate)
        let totals = dailyTotals.reduce(into: (income: 0.0, expense: 0.0)) { totals, entry in
            guard let interval, interval.start <= entry.key, entry.key < interval.end else { return }
            totals.income += entry.value.income
            totals.expense += entry.value.expense
        }
        return TransactionHeaderSection(
            selectedMonth: $selectedMonth,
            selectedDate: calendarDateBinding,
            period: $filter.period,
            keyword: $filter.keyword,
            dailyData: dailyTotals,
            income: totals.income,
            expense: totals.expense,
            onAdd: { showAdd = true }
        )
    }

    private var calendarDateBinding: Binding<Date?> {
        Binding(
            get: { selectedDate },
            set: { date in
                guard date != nil || filter.period == .month else { return }
                selectedDate = date
            }
        )
    }

    @ViewBuilder private var filterSection: some View {
        TransactionFilterSection(filter: $filter, categories: categories)
    }

    @ViewBuilder private func listSection(_ monthTransactions: [LocalTransaction]) -> some View {
        TransactionListSection(
            groups: displayedGroups(monthTransactions),
            isLoading: monthTransactions.isEmpty && sync.isSyncing,
            isFiltered: filter.hasContentFilter || filter.period != .month,
            onTap: { editing = $0 },
            onDeleteRequest: {
                pendingDeletion = $0
                showDeleteConfirmation = true
            }
        )
    }

    @ViewBuilder private func paginationSection(count: Int) -> some View {
        if usesPagination {
            TransactionPaginationSection(
                selectedDate: nil,
                hasMore: visibleCount < count,
                isLoadingMore: false,
                count: min(visibleCount, count),
                onLoadMore: { visibleCount += Self.pageSize }
            )
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            TransactionsInRange(monthWindow) { monthTransactions in
                List {
                    headerSection(monthTransactions)
                    filterSection
                    listSection(monthTransactions)
                    paginationSection(count: monthTransactions.count)
                }
                .listStyle(.grouped)
                .listSectionSpacing(8)
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
            }
            .appScreenHeader("Transactions")
            .refreshable { await sync.syncAll(modelContext: modelContext) }
            .onChange(of: selectedMonth) { _, month in
                visibleCount = Self.pageSize
                selectedDate = filter.period == .month ? nil : TransactionFilterEngine.defaultAnchor(for: month)
            }
            .onChange(of: filter.period) { _, period in
                if period == .month {
                    selectedDate = nil
                } else if selectedDate == nil {
                    selectedDate = TransactionFilterEngine.defaultAnchor(for: selectedMonth)
                }
            }
            .onChange(of: selectedDate) { _, date in
                if date != nil && filter.period == .month { filter.period = .day }
            }
            .sheet(isPresented: $showAdd) {
                AddEditTransactionView(transaction: nil, defaultDate: selectedDate)
            }
            .sheet(item: $editing) { tx in
                AddEditTransactionView(transaction: tx)
            }
            .deleteConfirmation(
                item: $pendingDeletion,
                isPresented: $showDeleteConfirmation,
                title: "Delete Transaction?",
                message: "The transaction will be permanently deleted and its wallet balance will be adjusted."
            ) { transaction in
                Task { await delete(transaction) }
            }
            .errorAlert($errorMessage)
        }
    }

    private func delete(_ transaction: LocalTransaction) async {
        do {
            try await TransactionService.shared.delete(transaction, in: modelContext)
        } catch {
            errorMessage = error.asDisplayableError().localizedDescription
        }
    }
}
