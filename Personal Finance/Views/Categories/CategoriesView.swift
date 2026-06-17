import SwiftUI
import SwiftData

struct CategoriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalCategory.name) private var categories: [LocalCategory]

    @State private var showAdd = false
    @State private var editing: LocalCategory?
    @State private var errorMsg: String?

    private var incomeCategories: [LocalCategory] { categories.filter { $0.type == "income" } }
    private var expenseCategories: [LocalCategory] { categories.filter { $0.type == "expense" } }

    var body: some View {
        List {
            if !incomeCategories.isEmpty {
                Section("Income") {
                    ForEach(incomeCategories, id: \.serverId) { cat in
                        CategoryRow(category: cat)
                            .onTapGesture { if !cat.isDefault { editing = cat } }
                            .swipeActions(edge: .trailing) {
                                if !cat.isDefault {
                                    Button(role: .destructive) {
                                        Task { await delete(cat) }
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                    }
                }
            }
            if !expenseCategories.isEmpty {
                Section("Expense") {
                    ForEach(expenseCategories, id: \.serverId) { cat in
                        CategoryRow(category: cat)
                            .onTapGesture { if !cat.isDefault { editing = cat } }
                            .swipeActions(edge: .trailing) {
                                if !cat.isDefault {
                                    Button(role: .destructive) {
                                        Task { await delete(cat) }
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Categories")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { AddEditCategoryView(category: nil) }
        .sheet(item: $editing) { cat in AddEditCategoryView(category: cat) }
        .alert("Error", isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })) {
            Button("OK") { errorMsg = nil }
        } message: { Text(errorMsg ?? "") }
    }

    private func delete(_ cat: LocalCategory) async {
        do {
            try await CategoryService.shared.delete(cat, in: modelContext)
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}

private struct CategoryRow: View {
    let category: LocalCategory
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((category.color.map { Color(hex: $0) } ?? .blue).opacity(0.15))
                    .frame(width: 40, height: 40)
                Text(category.icon ?? "📦").font(.system(size: 20))
            }
            Text(category.name).font(.body)
            Spacer()
            if category.isDefault {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
