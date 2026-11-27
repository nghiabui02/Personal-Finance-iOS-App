import SwiftUI

private struct DeleteConfirmationModifier<Item>: ViewModifier {
    @Binding var item: Item?
    @Binding var isPresented: Bool

    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let confirmLabel: LocalizedStringKey
    let onConfirm: (Item) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            title,
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button(confirmLabel, role: .destructive) {
                guard let item else { return }
                self.item = nil
                isPresented = false
                onConfirm(item)
            }
            Button("Cancel", role: .cancel) {
                item = nil
                isPresented = false
            }
        } message: {
            Text(message)
        }
    }
}

extension View {
    func deleteConfirmation<Item>(
        item: Binding<Item?>,
        isPresented: Binding<Bool>,
        title: LocalizedStringKey,
        message: LocalizedStringKey = "This action cannot be undone.",
        confirmLabel: LocalizedStringKey = "Delete",
        onConfirm: @escaping (Item) -> Void
    ) -> some View {
        modifier(
            DeleteConfirmationModifier(
                item: item,
                isPresented: isPresented,
                title: title,
                message: message,
                confirmLabel: confirmLabel,
                onConfirm: onConfirm
            )
        )
    }
}
