import SwiftUI
import SwiftData

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalCategory.name) private var categories: [LocalCategory]
    @StateObject private var vm   = TransactionViewModel()
    @Environment(\.scenePhase) private var scenePhase

    // UI-only state — does not drive data fetching
    @State private var selectedDate: Date? = Date()
    @State private var filter = TransactionFilterState()
    @State private var showAdd = false
    @State private var editing: LocalTransaction?
    @State private var pendingDeletion: LocalTransaction?
    @State private var showDeleteConfirmation = false

    // MARK: - Derived display values (pure computation from vm state)

    private var displayedIncome: Double {
        displayedTotals.income
    }

    private var displayedExpense: Double {
        displayedTotals.expense
    }

    private var displayedGroups: [(Date, [LocalTransaction])] {
        let transactions = TransactionFilterEngine.apply(
            filter,
            to: vm.loadedTxs,
            selectedMonth: vm.selectedMonth,
            selectedDate: selectedDate
        )
        return TransactionGroupingCalculator.group(transactions).all
    }

    private var displayedTotals: (income: Double, expense: Double) {
        guard filter.period != .month,
              let interval = TransactionFilterEngine.dateInterval(
                for: filter.period,
                selectedMonth: vm.selectedMonth,
                selectedDate: selectedDate
              ) else {
            return (vm.periodIncome, vm.periodExpense)
        }

        return vm.dailyData.reduce(into: (income: 0.0, expense: 0.0)) { totals, entry in
            guard entry.key >= interval.start, entry.key < interval.end else { return }
            totals.income += entry.value.income
            totals.expense += entry.value.expense
        }
    }

    // MARK: - Sub-views

    @ViewBuilder private var headerSection: some View {
        TransactionHeaderSection(
            selectedMonth: $vm.selectedMonth,
            selectedDate: calendarDateBinding,
            period: $filter.period,
            keyword: $filter.keyword,
            dailyData: vm.dailyData,
            income: displayedIncome,
            expense: displayedExpense,
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

    @ViewBuilder private var listSection: some View {
        TransactionListSection(
            groups: displayedGroups,
            isLoading: vm.loadedTxs.isEmpty && (vm.isLoadingMore || vm.isLoadingDateTxs),
            isFiltered: filter.hasContentFilter || filter.period != .month,
            onTap: { editing = $0 },
            onDeleteRequest: {
                pendingDeletion = $0
                showDeleteConfirmation = true
            }
        )
    }

    @ViewBuilder private var paginationSection: some View {
        TransactionPaginationSection(
            selectedDate: filter.period == .month ? nil : selectedDate,
            hasMore: vm.hasMore,
            isLoadingMore: vm.isLoadingMore,
            count: vm.loadedTxs.count,
            onLoadMore: { await vm.loadMore(in: modelContext) }
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                headerSection
                filterSection
                listSection
                paginationSection
            }
            .listStyle(.grouped)
            .listSectionSpacing(8)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .appScreenHeader("Transactions")
            .animation(.easeInOut(duration: 0.2), value: vm.isOnCurrentMonth)
            .refreshable { vm.resetAndLoad(in: modelContext) }
            .onChange(of: scenePhase)       { _, p in if p == .active { vm.resetAndLoad(in: modelContext) } }
            .onChange(of: vm.selectedMonth) { _, month in
                selectedDate = filter.period == .month
                    ? nil
                    : TransactionFilterEngine.defaultAnchor(for: month)
                vm.resetAndLoad(in: modelContext)
            }
            .onChange(of: filter.period) { _, period in
                if period == .month {
                    selectedDate = nil
                } else if selectedDate == nil {
                    selectedDate = TransactionFilterEngine.defaultAnchor(for: vm.selectedMonth)
                }
                loadSelectedPeriodIfNeeded(period: period, date: selectedDate)
            }
            .onChange(of: filter) { _, updatedFilter in
                guard updatedFilter.hasContentFilter else { return }
                Task { await vm.ensureAllTransactionsLoadedForFiltering(in: modelContext) }
            }
            .onChange(of: selectedDate) { _, date in
                guard let date else { return }
                if filter.period == .month {
                    filter.period = .day
                }
                loadSelectedPeriodIfNeeded(period: filter.period, date: date)
            }
            .onAppear {
                if vm.selectedMonth != vm.currentMonthStart {
                    vm.selectedMonth = vm.currentMonthStart
                } else if vm.loadedTxs.isEmpty {
                    vm.resetAndLoad(in: modelContext)
                }
                loadSelectedPeriodIfNeeded(period: filter.period, date: selectedDate)
            }
            .sheet(isPresented: $showAdd) {
                AddEditTransactionView(transaction: nil, defaultDate: selectedDate)
            }
            .sheet(item: $editing) { tx in AddEditTransactionView(transaction: tx) }
            .deleteConfirmation(
                item: $pendingDeletion,
                isPresented: $showDeleteConfirmation,
                title: "Delete Transaction?",
                message: "The transaction will be permanently deleted and its wallet balance will be adjusted."
            ) { transaction in
                Task { await vm.deleteTx(transaction, in: modelContext) }
            }
            .errorAlert($vm.errorMsg)
        }
    }

    private func loadSelectedPeriodIfNeeded(period: TransactionPeriodFilter, date: Date?) {
        guard period != .month else { return }
        Task {
            await vm.ensurePeriodLoaded(
                period,
                selectedMonth: vm.selectedMonth,
                selectedDate: date,
                in: modelContext
            )
        }
    }
}
