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

    private var categoryValue: AnyView {
        if let selectedCategory {
            return AnyView(
                HStack(spacing: 4) {
                    Text(selectedCategory.icon ?? "📦")
                    Text(selectedCategory.name)
                        .foregroundColor(.secondary)
                }
            )
        }

        return AnyView(Text("Select").foregroundColor(.secondary))
    }

    private var walletValue: AnyView {
        if let selectedWallet {
            return AnyView(Text(selectedWallet.name).foregroundColor(.secondary))
        }

        return AnyView(Text("Select").foregroundColor(.secondary))
    }
}

private struct TransactionSelectionRow<Value: View>: View {
    let title: String
    let value: Value
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(title)
                    .foregroundColor(.primary)
                Spacer()
                value
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
