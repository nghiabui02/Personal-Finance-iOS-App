import SwiftUI

struct BudgetProgressView: View {
    let budgets: [LocalBudget]
    let spendingByCategoryId: [String: Double]
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Budgets")
                .font(.headline)

            if budgets.isEmpty {
                Text("No budgets set for this month")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 14) {
                    ForEach(budgets) { budget in
                        BudgetRowView(
                            budget: budget,
                            spent: spendingByCategoryId[budget.categoryId] ?? 0,
                            currency: currency
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

private struct BudgetRowView: View {
    let budget: LocalBudget
    let spent: Double
    let currency: String

    private var progress: Double { min(spent / budget.amount, 1.0) }
    private var remaining: Double { budget.amount - spent }
    private var isOver: Bool { spent > budget.amount }

    private var barColor: Color {
        if isOver { return .red }
        if progress >= 0.8 { return .orange }
        return Color(hex: budget.categoryColor ?? "#3b82f6")
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(budget.categoryIcon ?? "📦")
                    .font(.subheadline)
                Text(budget.categoryName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if isOver {
                    Text("Over \(abs(remaining).formatted(currency: currency))")
                        .font(.caption)
                        .foregroundColor(.red)
                        .fontWeight(.medium)
                } else {
                    Text("\(remaining.formatted(currency: currency)) left")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(width: geo.size.width * progress, height: 8)
                        .animation(.easeInOut(duration: 0.4), value: progress)
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(spent.formatted(currency: currency)) spent")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("of \(budget.amount.formatted(currency: currency))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
