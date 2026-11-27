import SwiftUI
import SwiftData

struct BudgetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allBudgets: [LocalBudget]
    @Query private var allCategories: [LocalCategory]
    private var sync: SyncManager { .shared }

    @State private var selectedMonth = TransactionDateRange.monthStart(for: Date())
    @State private var showAdd = false
    @State private var editing: LocalBudget?
    @State private var pendingDeletion: LocalBudget?
    @State private var showDeleteConfirmation = false
    @State private var errorMsg: String?

    private var monthBudgets: [LocalBudget] {
        allBudgets.filter { LedgerDate.calendar.isDate($0.month, equalTo: selectedMonth, toGranularity: .month) }
    }

    /// The selected month plus the three before it that suggestions are drawn from.
    private var transactionWindow: Range<Date> {
        TransactionDateRange.including(
            budgetHistoryOf: allBudgets, for: selectedMonth,
            in: TransactionDateRange.window(endingWith: selectedMonth, monthsBefore: 3)
        )
    }

    private func suggestions(from transactions: [LocalTransaction]) -> [BudgetSuggestion] {
        BudgetSuggestionCalculator.calculate(
            transactions: transactions, categories: allCategories,
            existingBudgetCategoryIds: Set(monthBudgets.compactMap(\.categoryId)),
            targetMonth: selectedMonth
        )
    }

    var body: some View {
        TransactionsInRange(transactionWindow) { transactions in
            budgetScreen(transactions)
        }
    }

    private func budgetScreen(_ transactions: [LocalTransaction]) -> some View {
        let activeBudgets = monthBudgets.filter(\.active)
        let inactiveBudgets = monthBudgets.filter { !$0.active }
        let usage = BudgetUsageCalculator.calculate(
            budgets: allBudgets, operatingTransactions: transactions.operatingOnly(using: allCategories)
        )
        return VStack(spacing: 0) {
            MonthSelectorView(selectedMonth: $selectedMonth)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemGroupedBackground))

            List {
                suggestionsSection(suggestions(from: transactions))
                activeSection(activeBudgets, usage: usage)
                inactiveSection(inactiveBudgets, usage: usage)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .listStyle(.insetGrouped)
            .refreshable { await sync.syncAll(modelContext: modelContext) }
            .overlay {
                if monthBudgets.isEmpty {
                    ContentUnavailableView(
                        "No Budgets",
                        systemImage: "chart.bar",
                        description: Text("Tap + to add a budget for this month")
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Budgets")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddEditBudgetView(budget: nil, defaultMonth: selectedMonth)
        }
        .sheet(item: $editing) { budget in
            AddEditBudgetView(budget: budget, defaultMonth: selectedMonth)
        }
        .deleteConfirmation(
            item: $pendingDeletion,
            isPresented: $showDeleteConfirmation,
            title: "Delete Budget?",
            message: "The budget will be permanently deleted."
        ) { budget in
            Task { await delete(budget) }
        }
        .errorAlert($errorMsg)
    }

    @ViewBuilder
    private func suggestionsSection(_ suggestions: [BudgetSuggestion]) -> some View {
        if !suggestions.isEmpty {
            Section {
                ForEach(suggestions) { suggestion in
                    SuggestionRow(suggestion: suggestion) {
                        Task { await addSuggestion(suggestion) }
                    }
                }
            } header: {
                Text("Suggested")
            } footer: {
                Text("Based on the median of your last 3 months of spending.")
            }
        }
    }

    @ViewBuilder
    private func activeSection(_ budgets: [LocalBudget], usage: [UUID: BudgetUsage]) -> some View {
        if !budgets.isEmpty {
            Section("Active") {
                ForEach(budgets, id: \.serverId) { budget in
                    let spent = usage[budget.serverId]?.spent ?? 0
                    let effective = usage[budget.serverId]?.effectiveAmount ?? budget.amount
                    BudgetRow(budget: budget, spent: spent, effectiveAmount: effective)
                        .onTapGesture { editing = budget }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                pendingDeletion = budget
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                            Button {
                                Task { await toggleActive(budget, active: false) }
                            } label: {
                                Label("Pause", systemImage: "pause.circle")
                            }
                            .tint(.orange)
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func inactiveSection(_ budgets: [LocalBudget], usage: [UUID: BudgetUsage]) -> some View {
        if !budgets.isEmpty {
            Section("Inactive") {
                ForEach(budgets, id: \.serverId) { budget in
                    let spent = usage[budget.serverId]?.spent ?? 0
                    BudgetRow(budget: budget, spent: spent, effectiveAmount: budget.amount)
                        .foregroundStyle(.secondary)
                        .onTapGesture { editing = budget }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                pendingDeletion = budget
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                            Button {
                                Task { await toggleActive(budget, active: true) }
                            } label: {
                                Label("Reactivate", systemImage: "play.circle")
                            }
                            .tint(.green)
                        }
                }
            }
        }
    }

    private func addSuggestion(_ suggestion: BudgetSuggestion) async {
        do {
            try await BudgetService.shared.create(
                categoryId: suggestion.categoryId, amount: suggestion.amount,
                month: selectedMonth, in: modelContext
            )
        } catch { errorMsg = error.asDisplayableError().localizedDescription }
    }

    private func delete(_ budget: LocalBudget) async {
        do { try await BudgetService.shared.delete(budget, in: modelContext) }
        catch { errorMsg = error.asDisplayableError().localizedDescription }
    }

    private func toggleActive(_ budget: LocalBudget, active: Bool) async {
        do { try await BudgetService.shared.toggleActive(budget, active: active, in: modelContext) }
        catch { errorMsg = error.asDisplayableError().localizedDescription }
    }
}

private struct SuggestionRow: View {
    let suggestion: BudgetSuggestion
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill((suggestion.categoryColor.map { Color(hex: $0) } ?? .blue).opacity(0.15))
                    .frame(width: 36, height: 36)
                Text(suggestion.categoryIcon).font(.system(size: 16)).accessibilityHidden(true)
            }
            Text(suggestion.categoryName).fontWeight(.medium)
            Spacer()
            Text(suggestion.amount.formatted(currency: "VND"))
                .font(.subheadline).foregroundStyle(.secondary)
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill").foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

private struct BudgetRow: View {
    let budget: LocalBudget
    let spent: Decimal
    let effectiveAmount: Decimal

    private var progress: Double { effectiveAmount > 0 ? min((spent / effectiveAmount).doubleValue, 1.0) : 0 }
    private var remaining: Decimal { effectiveAmount - spent }
    private var overBudget: Bool { spent > effectiveAmount }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill((budget.categoryColor.map { Color(hex: $0) } ?? .blue).opacity(0.15))
                        .frame(width: 40, height: 40)
                    Text(budget.categoryIcon ?? "📦").font(.system(size: 20)).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(budget.categoryLabel).fontWeight(.medium)
                        if budget.rollover {
                            Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(.blue).font(.caption)
                        }
                        if !budget.active {
                            Text("Inactive").font(.caption2).foregroundStyle(.secondary)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(.secondary.opacity(0.15), in: Capsule())
                        }
                    }
                    Text("\(spent.formatted(currency: "VND")) / \(effectiveAmount.formatted(currency: "VND"))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(overBudget ? AppLocalization.shared.language.text("Over!") : remaining.formatted(currency: "VND"))
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(overBudget ? .red : .green)
                    Text("left").font(.caption2).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: progress)
                .tint(overBudget ? .red : progress > 0.8 ? .orange : .green)
        }
        .padding(.vertical, 4)
    }
}
