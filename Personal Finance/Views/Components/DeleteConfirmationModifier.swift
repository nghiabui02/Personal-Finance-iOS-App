import SwiftUI

private struct DeleteConfirmationModifier<Item>: ViewModifier {
    @Binding var item: Item?
    @Binding var isPresented: Bool

    let title: String
    let message: String
    let onConfirm: (Item) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            title,
            isPresented: $isPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
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
        title: String,
        message: String = "This action cannot be undone.",
        onConfirm: @escaping (Item) -> Void
    ) -> some View {
        modifier(
            DeleteConfirmationModifier(
                item: item,
                isPresented: isPresented,
                title: title,
                message: message,
                onConfirm: onConfirm
            )
        )
    }
}
