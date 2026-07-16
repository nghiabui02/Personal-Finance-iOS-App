import SwiftUI

struct TransactionFilterSection: View {
    @Binding var filter: TransactionFilterState
    let categories: [LocalCategory]

    private var availableCategories: [LocalCategory] {
        categories.filter { category in
            guard let type = filter.type.transactionType else { return true }
            return category.type == type
        }
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Transaction type", selection: $filter.type) {
                    ForEach(TransactionTypeFilter.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                categoryChips
            }
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowBackground(Color(.systemGroupedBackground))
        .listRowSeparator(.hidden)
        .onChange(of: filter.type) { _, _ in
            clearUnavailableCategory()
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                categoryChip(title: "All", icon: nil, categoryId: nil)

                ForEach(availableCategories, id: \.serverId) { category in
                    categoryChip(
                        title: category.name,
                        icon: category.icon,
                        categoryId: category.serverId
                    )
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }

    private func categoryChip(title: String, icon: String?, categoryId: UUID?) -> some View {
        let isSelected = filter.categoryId == categoryId

        return Button {
            filter.categoryId = categoryId
        } label: {
            HStack(spacing: 5) {
                if let icon, !icon.isEmpty {
                    Text(icon)
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Color(.systemBackground) : .primary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                isSelected ? Color.primary : Color(.secondarySystemGroupedBackground),
                in: Capsule()
            )
            .overlay {
                if !isSelected {
                    Capsule().stroke(Color(.separator).opacity(0.45), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func clearUnavailableCategory() {
        guard let categoryId = filter.categoryId else { return }
        if !availableCategories.contains(where: { $0.serverId == categoryId }) {
            filter.categoryId = nil
        }
    }
}
