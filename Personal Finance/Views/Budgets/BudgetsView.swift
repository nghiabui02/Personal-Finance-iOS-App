import SwiftUI
import SwiftData

struct BudgetsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allBudgets: [LocalBudget]
    @Query(sort: \LocalTransaction.transactionDate, order: .reverse) private var allTx: [LocalTransaction]

    @State private var selectedMonth: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date()))!
    @State private var showAdd = false
    @State private var editing: LocalBudget?
    @State private var errorMsg: String?

    // Cached — recomputed once via onChange, not every render
    @State private var cachedBudgets: [LocalBudget] = []
    @State private var cachedSpent: [UUID: Double] = [:]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MonthSelectorView(selectedMonth: $selectedMonth)
                    .padding(.horizontal).padding(.vertical, 8)
                    .background(Color(.systemBackground))

                if cachedBudgets.isEmpty {
                    ContentUnavailableView("No Budgets", systemImage: "chart.bar",
                        description: Text("Tap + to add a budget for this month"))
                        .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(cachedBudgets, id: \.serverId) { budget in
                            let spent = cachedSpent[budget.categoryId ?? UUID()] ?? 0
                            BudgetRow(budget: budget, spent: spent)
                                .onTapGesture { editing = budget }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        Task { await delete(budget) }
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Budgets")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .onAppear { recompute() }
            .onChange(of: allBudgets)    { _, _ in recompute() }
            .onChange(of: allTx)         { _, _ in recompute() }
            .onChange(of: selectedMonth) { _, _ in recompute() }
            .sheet(isPresented: $showAdd) { AddEditBudgetView(budget: nil, defaultMonth: selectedMonth) }
            .sheet(item: $editing) { b in AddEditBudgetView(budget: b, defaultMonth: selectedMonth) }
            .alert("Error", isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })) {
                Button("OK") { errorMsg = nil }
            } message: { Text(errorMsg ?? "") }
        }
    }

    // Single pass: filter budgets + compute spent — O(n_budgets + n_transactions)
    private func recompute() {
        let cal = Calendar.current
        cachedBudgets = allBudgets.filter {
            cal.isDate($0.month, equalTo: selectedMonth, toGranularity: .month)
        }
        var spent: [UUID: Double] = [:]
        for tx in allTx where tx.type == "expense" &&
            cal.isDate(tx.transactionDate, equalTo: selectedMonth, toGranularity: .month) {
            if let id = tx.categoryId { spent[id, default: 0] += tx.amount }
        }
        cachedSpent = spent
    }

    private func delete(_ budget: LocalBudget) async {
        do { try await BudgetService.shared.delete(budget, in: modelContext) }
        catch { errorMsg = error.localizedDescription }
    }
}

private struct BudgetRow: View {
    let budget: LocalBudget
    let spent: Double

    private var progress: Double { budget.amount > 0 ? min(spent / budget.amount, 1.0) : 0 }
    private var remaining: Double { budget.amount - spent }
    private var overBudget: Bool { spent > budget.amount }

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
                    Text(budget.categoryName).fontWeight(.medium)
                    Text("\(spent.formatted(currency: "VND")) / \(budget.amount.formatted(currency: "VND"))")
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
