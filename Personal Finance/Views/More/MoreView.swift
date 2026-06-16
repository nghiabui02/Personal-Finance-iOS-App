import SwiftUI

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { CategoriesView() } label: {
                        Label("Categories", systemImage: "tag.fill")
                    }
                    NavigationLink { BudgetsView() } label: {
                        Label("Budgets", systemImage: "chart.bar.fill")
                    }
                }
                Section {
                    NavigationLink { DebtsView() } label: {
                        Label("Debts", systemImage: "dollarsign.circle.fill")
                    }
                    NavigationLink { SavingGoalsView() } label: {
                        Label("Saving Goals", systemImage: "star.fill")
                    }
                    NavigationLink { RecurringView() } label: {
                        Label("Recurring", systemImage: "arrow.clockwise")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("More")
        }
    }
}
