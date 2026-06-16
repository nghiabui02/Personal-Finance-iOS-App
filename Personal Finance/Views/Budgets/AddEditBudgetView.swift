import SwiftUI
import SwiftData

struct AddEditBudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let budget: LocalBudget?
    let defaultMonth: Date

    @Query(sort: \LocalCategory.name) private var allCategories: [LocalCategory]

    @State private var selectedCategoryId: UUID?
    @State private var amount: Double = 0
    @State private var amountText = ""
    @State private var month: Date
    @State private var isSaving = false
    @State private var errorMsg: String?

    init(budget: LocalBudget?, defaultMonth: Date) {
        self.budget = budget
        self.defaultMonth = defaultMonth
        _month = State(initialValue: defaultMonth)
    }

    private var expenseCategories: [LocalCategory] { allCategories.filter { $0.type == "expense" } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if budget == nil {
                        DatePicker("Month", selection: $month, displayedComponents: [.date])
                            .environment(\.locale, Locale(identifier: "en_US"))
                        Picker("Category", selection: $selectedCategoryId) {
                            Text("None").tag(UUID?.none)
                            ForEach(expenseCategories, id: \.serverId) { cat in
                                Text("\(cat.icon ?? "📦") \(cat.name)").tag(Optional(cat.serverId))
                            }
                        }
                    } else {
                        HStack {
                            Text("Category")
                            Spacer()
                            Text(budget?.categoryName ?? "").foregroundColor(.secondary)
                        }
                    }
                    HStack {
                        Text("Budget Amount")
                        Spacer()
                        TextField("0", text: $amountText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .fontWeight(.semibold)
                            .onChange(of: amountText) { _, new in
                                applyAmountFormat(new: new, amountText: &amountText, amount: &amount)
                            }
                        Text("₫").foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(budget != nil ? "Edit Budget" : "New Budget")
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
        .onAppear {
            if let b = budget {
                amount = b.amount
                amountText = b.amount.formattedDecimal()
                month = b.month
            }
        }
    }

    private func save() async {
        guard amount > 0 else { return }
        isSaving = true; defer { isSaving = false }
        do {
            if let b = budget {
                try await BudgetService.shared.update(b, amount: amount, in: modelContext)
            } else {
                try await BudgetService.shared.create(categoryId: selectedCategoryId, amount: amount, month: month, in: modelContext)
            }
            dismiss()
        } catch { errorMsg = error.localizedDescription }
    }
}
