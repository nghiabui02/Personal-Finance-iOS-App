import SwiftUI
import SwiftData

struct AddEditBudgetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let budget: LocalBudget?
    let defaultMonth: Date

    @Query(sort: \LocalCategory.name) private var allCategories: [LocalCategory]

    @State private var selectedCategoryId: UUID?
    @State private var amount: Decimal = 0
    @State private var amountText = ""
    @State private var month: Date
    @State private var rollover = false
    @State private var active = true
    @State private var isSaving = false
    @State private var errorMsg: String?

    init(budget: LocalBudget?, defaultMonth: Date) {
        self.budget = budget
        self.defaultMonth = defaultMonth
        _month = State(initialValue: defaultMonth)
    }

    private var expenseCategories: [LocalCategory] {
        allCategories.filter { $0.type == .expense && $0.systemKey == nil && $0.isActiveMembership }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if budget == nil {
                        DatePicker("Month", selection: $month, displayedComponents: [.date])
                        Picker("Category", selection: $selectedCategoryId) {
                            Text("None").tag(UUID?.none)
                            ForEach(expenseCategories, id: \.serverId) { cat in
                                Text("\(cat.icon ?? "📦") \(cat.displayName)").tag(Optional(cat.serverId))
                            }
                        }
                    } else {
                        HStack {
                            Text("Category")
                            Spacer()
                            Text(budget?.categoryLabel ?? "").foregroundStyle(.secondary)
                        }
                    }
                    CurrencyAmountField(
                        title: "Budget Amount",
                        amount: $amount,
                        amountText: $amountText
                    )
                    Toggle("Rollover", isOn: $rollover)
                    if budget != nil {
                        Toggle("Active", isOn: $active)
                    }
                }
            }
            .formKeyboardHandling()
            .navigationTitle(budget != nil ? "Edit Budget" : "New Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView().scaleEffect(0.8) } else {
                        Button("Save") { Task { await save() } }
                            .disabled(!Self.canSave(amount: amount, isNew: budget == nil, categoryId: selectedCategoryId))
                    }
                }
            }
            .errorAlert($errorMsg)
        }
        .onAppear {
            if let b = budget {
                amount = b.amount
                amountText = b.amount.formattedDecimal()
                month = b.month
                rollover = b.rollover
                active = b.active
            }
        }
    }

    /// A new budget needs a category: one without tracks no spending, so it would always show 0 spent.
    static func canSave(amount: Decimal, isNew: Bool, categoryId: UUID?) -> Bool {
        amount > 0 && (!isNew || categoryId != nil)
    }

    private func save() async {
        guard Self.canSave(amount: amount, isNew: budget == nil, categoryId: selectedCategoryId) else { return }
        isSaving = true; defer { isSaving = false }
        do {
            if let b = budget {
                try await BudgetService.shared.update(b, amount: amount, rollover: rollover, active: active, in: modelContext)
            } else {
                try await BudgetService.shared.create(
                    categoryId: selectedCategoryId, amount: amount, month: month, rollover: rollover, in: modelContext)
            }
            dismiss()
        } catch { errorMsg = error.asDisplayableError().localizedDescription }
    }
}
