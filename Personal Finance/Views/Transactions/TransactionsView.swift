import SwiftUI
import SwiftData

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var vm   = TransactionViewModel()
    @Environment(\.scenePhase) private var scenePhase

    // UI-only state — does not drive data fetching
    @State private var selectedDate: Date? = nil
    @State private var filterType: FilterType = .all
    @State private var showAdd = false
    @State private var editing: LocalTransaction?

    // MARK: - Derived display values (pure computation from vm state)

    private var displayedIncome: Double {
        guard let date = selectedDate else { return vm.periodIncome }
        return vm.dailyData[Calendar.current.startOfDay(for: date)]?.income ?? 0
    }

    private var displayedExpense: Double {
        guard let date = selectedDate else { return vm.periodExpense }
        return vm.dailyData[Calendar.current.startOfDay(for: date)]?.expense ?? 0
    }

    private var displayedGroups: [(Date, [LocalTransaction])] {
        let base: [(Date, [LocalTransaction])]
        switch filterType {
        case .all:     base = vm.groupedAll
        case .income:  base = vm.groupedIncome
        case .expense: base = vm.groupedExpense
        }
        guard let date = selectedDate else { return base }
        return base.filter { Calendar.current.isDate($0.0, inSameDayAs: date) }
    }

    // MARK: - Sub-views

    @ViewBuilder private var headerSection: some View {
        TransactionHeaderSection(
            selectedMonth: $vm.selectedMonth,
            selectedDate: $selectedDate,
            filterType: $filterType,
            dailyData: vm.dailyData,
            income: displayedIncome,
            expense: displayedExpense
        )
    }

    @ViewBuilder private var listSection: some View {
        TransactionListSection(
            groups: displayedGroups,
            isLoading: vm.loadedTxs.isEmpty && (vm.isLoadingMore || vm.isLoadingDateTxs),
            onTap: { editing = $0 },
            onDelete: { await vm.deleteTx($0, in: modelContext) }
        )
    }

    @ViewBuilder private var paginationSection: some View {
        TransactionPaginationSection(
            selectedDate: selectedDate,
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
                listSection
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
                    if !vm.isOnCurrentMonth {
                        Button("Today") {
                            selectedDate = nil
                            vm.jumpToToday()
                        }
                        .font(.subheadline)
                        .transition(.opacity)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: vm.isOnCurrentMonth)
            .refreshable { vm.resetAndLoad(in: modelContext) }
            .onChange(of: scenePhase)       { _, p in if p == .active { vm.resetAndLoad(in: modelContext) } }
            .onChange(of: vm.selectedMonth) { _, _ in selectedDate = nil; vm.resetAndLoad(in: modelContext) }
            .onChange(of: selectedDate) { _, date in
                guard let date else { return }
                Task { await vm.ensureDateLoaded(date, in: modelContext) }
            }
            .onAppear {
                if vm.selectedMonth != vm.currentMonthStart {
                    vm.selectedMonth = vm.currentMonthStart
                } else if vm.loadedTxs.isEmpty {
                    vm.resetAndLoad(in: modelContext)
                }
            }
            .sheet(isPresented: $showAdd) {
                AddEditTransactionView(transaction: nil, defaultDate: selectedDate)
            }
            .sheet(item: $editing) { tx in AddEditTransactionView(transaction: tx) }
            .errorAlert($vm.errorMsg)
        }
    }
}
