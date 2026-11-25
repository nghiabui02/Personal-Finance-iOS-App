import SwiftUI
import SwiftData
import Supabase

struct CategoriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalCategory.name) private var categories: [LocalCategory]
    private var sync: SyncManager { .shared }

    @State private var selectedType = "expense"
    @State private var showAdd = false
    @State private var showStore = false
    @State private var isSaving = false
    @State private var dependencies: CategoryDependencies?
    @State private var editing: LocalCategory?
    @State private var pendingDeletion: LocalCategory?
    @State private var showDeleteConfirmation = false
    @State private var errorMsg: String?

    private var filtered: [LocalCategory] {
        categories.filter { $0.type == selectedType }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Picker("Type", selection: $selectedType) {
                    Text("Expense").tag("expense")
                    Text("Income").tag("income")
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 24)

                categorySection("My categories", rows: filtered.filter { $0.systemKey == nil && $0.isActiveMembership })
                categorySection("System categories", rows: filtered.filter { $0.systemKey != nil })
                categorySection("Removed categories", rows: filtered.filter { !$0.isActiveMembership })

                if filtered.isEmpty && !sync.isSyncing {
                    ContentUnavailableView(
                        "No Categories",
                        systemImage: "tag",
                        description: Text("Add a category from the Store or create your own.")
                    )
                    .padding(.top, 40)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showStore = true } label: { Label("Category Store", systemImage: "storefront") }
                Button { showAdd = true } label: { Label("New Category", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showStore) { CategoryStoreView() }
        .sheet(item: $dependencies) { CategoryDependencySheet(dependencies: $0) }
        .refreshable { await sync.syncAll(modelContext: modelContext) }
        .onAppear { Task { @MainActor in await sync.syncAll(modelContext: modelContext) } }
        .sheet(isPresented: $showAdd) { AddEditCategoryView(category: nil) }
        .sheet(item: $editing) { cat in AddEditCategoryView(category: cat) }
        .deleteConfirmation(
            item: $pendingDeletion,
            isPresented: $showDeleteConfirmation,
            title: "Remove Category?",
            message: "Past records will keep this category."
        ) { category in
            Task { await setActive(category, false) }
        }
        .errorAlert($errorMsg)
    }

    @ViewBuilder
    private func categorySection(_ title: LocalizedStringKey, rows: [LocalCategory]) -> some View {
        if !rows.isEmpty {
            CategorySection(title: title) {
                ForEach(rows, id: \.serverId) { category in
                    CategoryCard(category: category, onEdit: {
                        editing = category
                    }, onRemove: {
                        pendingDeletion = category
                        showDeleteConfirmation = true
                    }, onRestore: {
                        Task { await setActive(category, true) }
                    })
                    .disabled(isSaving)
                }
            }
        }
    }

    private func setActive(_ category: LocalCategory, _ active: Bool) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            if !active, try await showDependenciesIfNeeded(for: category) { return }
            try await CategoryService.shared.setActive(category, active, in: modelContext)
        } catch is CancellationError {
            return
        } catch {
            let removalBlocked = (error as? PostgrestError)?.code == "UC003"
            if !active && removalBlocked {
                do {
                    if try await showDependenciesIfNeeded(for: category) { return }
                } catch is CancellationError {
                    return
                } catch {
                    errorMsg = error.asDisplayableError().localizedDescription
                    return
                }
            }
            errorMsg = error.asDisplayableError().localizedDescription
        }
    }

    private func showDependenciesIfNeeded(for category: LocalCategory) async throws -> Bool {
        let result = try await CategoryService.shared.dependencies(for: category)
        guard !result.isEmpty else { return false }
        dependencies = result
        return true
    }
}

private struct CategoryDependencySheet: View {
    @Environment(\.dismiss) private var dismiss
    let dependencies: CategoryDependencies

    var body: some View {
        NavigationStack {
            List {
                Text("Pause or change these items before removing the category.")
                if !dependencies.budgets.isEmpty {
                    Section("Budgets") {
                        ForEach(dependencies.budgets) { budget in
                            LabeledContent("Current month", value: budget.amount.formatted(currency: "VND"))
                        }
                    }
                }
                if !dependencies.recurring.isEmpty {
                    Section("Recurring") {
                        ForEach(dependencies.recurring) { entry in
                            let note = entry.note ?? ""
                            let amount = entry.amount.formatted(currency: "VND")
                            let scheduled = entry.nextRunDate ?? ""
                            VStack(alignment: .leading) {
                                Text(note.isEmpty ? amount : note)
                                if !scheduled.isEmpty {
                                    Text("Next run: \(scheduled)").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Category in use")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Section container

private struct CategorySection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            VStack(spacing: 8) {
                content()
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 24)
    }
}

// MARK: - Category card row

private struct CategoryCard: View {
    let category: LocalCategory
    let onEdit: () -> Void
    let onRemove: () -> Void
    let onRestore: () -> Void

    private var accentColor: Color {
        category.color.map { Color(hex: $0) } ?? .blue
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                Text(category.icon ?? "📦")
                    .font(.system(size: 24))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(category.displayName)
                    .font(.body)
                    .foregroundColor(.primary)
                if category.isDefault && category.systemKey == nil {
                    Text("From Store")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Circle()
                .fill(accentColor)
                .frame(width: 10, height: 10)

            if !category.isActiveMembership {
                Button("Restore", action: onRestore).buttonStyle(.bordered)
            } else if category.systemKey == nil {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit Category")

                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove Category")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .cardBackground()
    }
}
