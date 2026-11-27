import SwiftUI

struct TransactionDetailsSection: View {
    @Binding var date: Date

    let selectedCategory: LocalCategory?
    let selectedWallet: LocalWallet?
    let onSelectCategory: () -> Void
    let onSelectWallet: () -> Void

    var body: some View {
        Section {
            DatePicker("Date", selection: $date, displayedComponents: .date)

            TransactionSelectionRow(
                title: "Category",
                value: categoryValue,
                onTap: onSelectCategory
            )

            TransactionSelectionRow(
                title: "Wallet",
                value: walletValue,
                onTap: onSelectWallet
            )
        }
    }

    @ViewBuilder
    private var categoryValue: some View {
        if let selectedCategory {
            HStack(spacing: 4) {
                Text(selectedCategory.icon ?? "📦")
                Text(selectedCategory.displayName)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Select").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var walletValue: some View {
        if let selectedWallet {
            Text(selectedWallet.name).foregroundStyle(.secondary)
        } else {
            Text("Select").foregroundStyle(.secondary)
        }
    }
}

private struct TransactionSelectionRow<Value: View>: View {
    let title: LocalizedStringKey
    let value: Value
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                value
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
