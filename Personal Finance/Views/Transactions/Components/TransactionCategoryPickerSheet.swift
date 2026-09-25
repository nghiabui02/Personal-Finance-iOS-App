import SwiftUI

struct TransactionCategoryPickerSheet: View {
    let categories: [LocalCategory]
    @Binding var selected: UUID?
    @Binding var isPresented: Bool

    @State private var search = ""

    private var displayedCategories: [LocalCategory] {
        search.isEmpty
            ? categories
            : categories.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if displayedCategories.isEmpty {
                    ContentUnavailableView("No Categories", systemImage: "tag")
                } else {
                    List(displayedCategories, id: \.serverId) { category in
                        Button {
                            selected = category.serverId
                            isPresented = false
                        } label: {
                            categoryRow(category)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .searchable(text: $search, prompt: "Search")
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }

    private func categoryRow(_ category: LocalCategory) -> some View {
        HStack(spacing: 12) {
            Text(category.icon ?? "📦")
                .font(.title3)
            Text(category.name)
                .foregroundColor(.primary)
            Spacer()
            if selected == category.serverId {
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
            }
        }
    }
}
