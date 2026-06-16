import SwiftUI
import SwiftData

struct SavingGoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalSavingGoal.name) private var goals: [LocalSavingGoal]

    @State private var showAdd = false
    @State private var editing: LocalSavingGoal?
    @State private var contributing: LocalSavingGoal?
    @State private var filterStatus: String = "active"
    @State private var errorMsg: String?

    private var filtered: [LocalSavingGoal] {
        filterStatus == "all" ? goals : goals.filter { $0.status == filterStatus }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filter", selection: $filterStatus) {
                    Text("Active").tag("active")
                    Text("Completed").tag("completed")
                    Text("All").tag("all")
                }
                .pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))

                if filtered.isEmpty {
                    ContentUnavailableView("No Goals", systemImage: "star.circle",
                        description: Text("Tap + to add a saving goal"))
                        .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filtered, id: \.serverId) { goal in
                            GoalRow(goal: goal)
                                .onTapGesture { editing = goal }
                                .swipeActions(edge: .leading) {
                                    if goal.status == "active" {
                                        Button { contributing = goal } label: {
                                            Label("Add", systemImage: "plus.circle")
                                        }.tint(.green)
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        Task { await delete(goal) }
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Saving Goals")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { AddEditSavingGoalView(goal: nil) }
            .sheet(item: $editing) { g in AddEditSavingGoalView(goal: g) }
            .sheet(item: $contributing) { g in ContributionSheet(goal: g) }
            .alert("Error", isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })) {
                Button("OK") { errorMsg = nil }
            } message: { Text(errorMsg ?? "") }
        }
    }

    private func delete(_ goal: LocalSavingGoal) async {
        do { try await SavingGoalService.shared.delete(goal, in: modelContext) }
        catch { errorMsg = error.localizedDescription }
    }
}

private struct GoalRow: View {
    let goal: LocalSavingGoal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.yellow.opacity(0.15)).frame(width: 44, height: 44)
                    Text(goal.icon ?? "🎯").font(.system(size: 22))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.name).fontWeight(.medium)
                    if let dl = goal.deadline {
                        Text("Due \(dl.formatted(.dateTime.month(.abbreviated).day().year()))")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(goal.currentAmount.formatted(currency: "VND"))
                        .fontWeight(.semibold)
                    Text("of \(goal.targetAmount.formatted(currency: "VND"))")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            ProgressView(value: goal.progress)
                .tint(goal.status == "completed" ? .green : .yellow)
            Text("\(Int(goal.progress * 100))% complete")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Contribution Sheet

struct ContributionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let goal: LocalSavingGoal

    @State private var amount: Double = 0
    @State private var isSaving = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0", value: $amount, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).fontWeight(.semibold)
                        Text("₫").foregroundColor(.secondary)
                    }
                }
                Section {
                    HStack {
                        Text("Current")
                        Spacer()
                        Text(goal.currentAmount.formatted(currency: "VND")).foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Target")
                        Spacer()
                        Text(goal.targetAmount.formatted(currency: "VND")).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Add Contribution")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView().scaleEffect(0.8) }
                    else {
                        Button("Save") { Task { await save() } }
                            .disabled(amount <= 0)
                    }
                }
            }
            .alert("Error", isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })) {
                Button("OK") { errorMsg = nil }
            } message: { Text(errorMsg ?? "") }
        }
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        do {
            try await SavingGoalService.shared.addContribution(goal, amount: amount, in: modelContext)
            dismiss()
        } catch { errorMsg = error.localizedDescription }
    }
}
