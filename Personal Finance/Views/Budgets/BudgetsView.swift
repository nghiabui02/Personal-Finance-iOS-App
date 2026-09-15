import SwiftUI
import SwiftData

struct BudgetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allBudgets: [LocalBudget]
    @Query(sort: \LocalTransaction.transactionDate, order: .reverse) private var allTx: [LocalTransaction]
    @Query private var allCategories: [LocalCategory]
    @StateObject private var sync = SyncManager.shared

    @State private var selectedMonth: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date()))!
    @State private var showAdd = false
    @State private var editing: LocalBudget?
    @State private var pendingDeletion: LocalBudget?
    @State private var showDeleteConfirmation = false
    @State private var errorMsg: String?

    // Cached — recomputed once via onChange, not every render
    @State private var cachedBudgets: [LocalBudget] = []
    @State private var cachedInactiveBudgets: [LocalBudget] = []
    @State private var cachedSpent: [UUID: Double] = [:]
    @State private var cachedEffective: [UUID: Double] = [:]
    @State private var suggestions: [BudgetSuggestion] = []

    var body: some View {
        VStack(spacing: 0) {
            MonthSelectorView(selectedMonth: $selectedMonth)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemGroupedBackground))

            List {
                suggestionsSection
                activeSection
                inactiveSection
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .listStyle(.insetGrouped)
            .refreshable { await sync.syncAll(modelContext: modelContext) }
            .overlay {
                if cachedBudgets.isEmpty && cachedInactiveBudgets.isEmpty {
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
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .onAppear { recompute() }
        .onChange(of: allBudgets)    { _, _ in recompute() }
        .onChange(of: allTx)         { _, _ in recompute() }
        .onChange(of: allCategories) { _, _ in recompute() }
        .onChange(of: selectedMonth) { _, _ in recompute() }
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
    private var suggestionsSection: some View {
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
    private var activeSection: some View {
        if !cachedBudgets.isEmpty {
            Section("Active") {
                ForEach(cachedBudgets, id: \.serverId) { budget in
                    let spent = cachedSpent[budget.categoryId ?? UUID()] ?? 0
                    let effective = cachedEffective[budget.serverId] ?? budget.amount
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
    private var inactiveSection: some View {
        if !cachedInactiveBudgets.isEmpty {
            Section("Inactive") {
                ForEach(cachedInactiveBudgets, id: \.serverId) { budget in
                    let spent = cachedSpent[budget.categoryId ?? UUID()] ?? 0
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

    // Single pass: filter budgets + compute spent + rollover effective amounts
    private func recompute() {
        let cal = Calendar.current
        let monthBudgets = allBudgets.filter {
            cal.isDate($0.month, equalTo: selectedMonth, toGranularity: .month)
        }
        cachedBudgets = monthBudgets.filter { $0.active }
        cachedInactiveBudgets = monthBudgets.filter { !$0.active }

        // Build spent map: (categoryId, monthStart) → total
        var spentMap: [UUID: [Date: Double]] = [:]
        for tx in allTx where tx.type == "expense" {
            guard let catId = tx.categoryId else { continue }
            let key = cal.date(from: cal.dateComponents([.year, .month], from: tx.transactionDate)) ?? tx.transactionDate
            spentMap[catId, default: [:]][key, default: 0] += tx.amount
        }

        // Spent for selected month (quick lookup for display)
        var spent: [UUID: Double] = [:]
        let selectedKey = cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth)) ?? selectedMonth
        for (catId, monthMap) in spentMap {
            if let s = monthMap[selectedKey] { spent[catId] = s }
        }
        cachedSpent = spent

        // Rollover effective amounts for active budgets
        var effective: [UUID: Double] = [:]
        for budget in cachedBudgets {
            effective[budget.serverId] = computeEffective(budget, spentMap: spentMap, cal: cal)
        }
        cachedEffective = effective

        let existingCategoryIds = Set(monthBudgets.compactMap(\.categoryId))
        suggestions = BudgetSuggestionCalculator.calculate(
            transactions: allTx,
            categories: allCategories,
            existingBudgetCategoryIds: existingCategoryIds,
            targetMonth: selectedMonth,
            calendar: cal
        )
    }

    private func addSuggestion(_ suggestion: BudgetSuggestion) async {
        do {
            try await BudgetService.shared.create(
                categoryId: suggestion.categoryId, amount: suggestion.amount,
                month: selectedMonth, in: modelContext
            )
        } catch { errorMsg = error.localizedDescription }
    }

    // Walk backwards through rollover chain, compute effective amount for this month.
    // effectiveAmount(M) = amount(M) + (rollover(M) ? leftover(M-1) : 0)
    // leftover(M) = effectiveAmount(M) - spent(M); chain breaks on gap/inactive/rollover=false
    private func computeEffective(_ budget: LocalBudget, spentMap: [UUID: [Date: Double]], cal: Calendar) -> Double {
        guard budget.rollover, let catId = budget.categoryId else { return budget.amount }

        // Collect chain: walk backwards until gap/inactive/rollover=false (max 12 months)
        var chain: [LocalBudget] = []
        var checkMonth = cal.date(byAdding: .month, value: -1, to: budget.month) ?? budget.month
        for _ in 0..<12 {
            guard let prev = allBudgets.first(where: {
                $0.categoryId == catId &&
                cal.isDate($0.month, equalTo: checkMonth, toGranularity: .month) &&
                $0.active && $0.rollover
            }) else { break }
            chain.insert(prev, at: 0)
            checkMonth = cal.date(byAdding: .month, value: -1, to: checkMonth) ?? checkMonth
        }
        chain.append(budget)

        // Compute forward through chain; carry leftover (positive or negative)
        var carry: Double = 0
        for (i, b) in chain.enumerated() {
            let key = cal.date(from: cal.dateComponents([.year, .month], from: b.month)) ?? b.month
            let s = spentMap[catId]?[key] ?? 0
            let eff = b.amount + carry
            if i < chain.count - 1 { carry = eff - s }
            else { return eff }
        }
        return budget.amount
    }

    private func delete(_ budget: LocalBudget) async {
        do { try await BudgetService.shared.delete(budget, in: modelContext) }
        catch { errorMsg = error.localizedDescription }
    }

    private func toggleActive(_ budget: LocalBudget, active: Bool) async {
        do { try await BudgetService.shared.toggleActive(budget, active: active, in: modelContext) }
        catch { errorMsg = error.localizedDescription }
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
                Text(suggestion.categoryIcon).font(.system(size: 16))
            }
            Text(suggestion.categoryName).fontWeight(.medium)
            Spacer()
            Text(suggestion.amount.formatted(currency: "VND"))
                .font(.subheadline).foregroundColor(.secondary)
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
    let spent: Double
    let effectiveAmount: Double

    private var progress: Double { effectiveAmount > 0 ? min(spent / effectiveAmount, 1.0) : 0 }
    private var remaining: Double { effectiveAmount - spent }
    private var overBudget: Bool { spent > effectiveAmount }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill((budget.categoryColor.map { Color(hex: $0) } ?? .blue).opacity(0.15))
                        .frame(width: 40, height: 40)
                    Text(budget.categoryIcon ?? "📦").font(.system(size: 20))
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(budget.categoryName).fontWeight(.medium)
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
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(overBudget ? "Over!" : remaining.formatted(currency: "VND"))
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(overBudget ? .red : .green)
                    Text("left").font(.caption2).foregroundColor(.secondary)
                }
            }
            ProgressView(value: progress)
                .tint(overBudget ? .red : progress > 0.8 ? .orange : .green)
        }
        .padding(.vertical, 4)
    }
}
