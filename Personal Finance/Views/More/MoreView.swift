import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var authVM: AuthViewModel

    var body: some View {
        NavigationStack {
            List {
                // Profile header
                Section {
                    NavigationLink { SettingsView().environmentObject(authVM) } label: {
                        HStack(spacing: 14) {
                            AvatarView(url: authVM.avatarURL, size: 52)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(authVM.displayName)
                                    .font(.headline)
                                Text(authVM.userEmail)
                                    .font(.subheadline).foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }

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
            .appScreenHeader("More")
        }
    }
}
