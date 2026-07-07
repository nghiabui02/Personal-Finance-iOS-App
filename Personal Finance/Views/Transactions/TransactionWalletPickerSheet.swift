import SwiftUI

struct TransactionWalletPickerSheet: View {
    let wallets: [LocalWallet]
    @Binding var selected: UUID?
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List(wallets, id: \.serverId) { wallet in
                Button {
                    selected = wallet.serverId
                    isPresented = false
                } label: {
                    walletRow(wallet)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }

    private func walletRow(_ wallet: LocalWallet) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((wallet.color.map { Color(hex: $0) } ?? .blue).opacity(0.15))
                    .frame(width: 36, height: 36)
                Text(wallet.displayIcon)
                    .font(.system(size: 18))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(wallet.name)
                    .foregroundColor(.primary)
                    .fontWeight(.medium)
                Text(wallet.balance.formatted(currency: "VND"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if selected == wallet.serverId {
                Image(systemName: "checkmark")
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 2)
    }
}
