import SwiftUI
import SwiftData

struct CategoriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalCategory.name) private var categories: [LocalCategory]

    @State private var selectedType = "expense"
    @State private var showAdd = false
    @State private var editing: LocalCategory?
    @State private var errorMsg: String?
    @State private var isSyncing = false

    private var filtered: [LocalCategory] { categories.filter { $0.type == selectedType } }
    private var customCategories: [LocalCategory] { filtered.filter { !$0.isDefault } }
    private var defaultCategories: [LocalCategory] { filtered.filter { $0.isDefault } }

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

                if !customCategories.isEmpty {
                    CategorySection(title: "CUSTOM") {
                        ForEach(customCategories, id: \.serverId) { cat in
                            CategoryCard(category: cat, isDefault: false) {
                                editing = cat
                            } onDelete: {
                                Task { await delete(cat) }
                            }
                        }
                    }
                }

                if !defaultCategories.isEmpty {
                    CategorySection(title: "DEFAULT") {
                        ForEach(defaultCategories, id: \.serverId) { cat in
                            CategoryCard(category: cat, isDefault: true, onEdit: {}, onDelete: {})
                        }
                    }
                }

                if filtered.isEmpty && !isSyncing {
                    ContentUnavailableView(
                        "No Categories",
                        systemImage: "tag",
                        description: Text("Tap + to add a category")
                    )
                    .padding(.top, 40)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Categories")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSyncing {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .refreshable { await syncCategories() }
        .onAppear { Task { await syncCategories() } }
        .sheet(isPresented: $showAdd) { AddEditCategoryView(category: nil) }
        .sheet(item: $editing) { cat in AddEditCategoryView(category: cat) }
        .alert("Error", isPresented: Binding(
            get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } }
        )) { Button("OK") { errorMsg = nil } } message: { Text(errorMsg ?? "") }
    }

    private func syncCategories() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await CategoryService.shared.sync(in: modelContext)
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func delete(_ cat: LocalCategory) async {
        do {
            try await CategoryService.shared.delete(cat, in: modelContext)
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}

// MARK: - Section container

private struct CategorySection<Content: View>: View {
    let title: String
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
    let isDefault: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

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
                Text(category.name)
                    .font(.body)
                    .foregroundColor(.primary)
                if isDefault {
                    Text("Default")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Circle()
                .fill(accentColor)
                .frame(width: 10, height: 10)

            if !isDefault {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .cardBackground()
    }
}
