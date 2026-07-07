import SwiftUI

struct WalletRow: View {
    let wallet: LocalWallet

    private var accentColor: Color {
        wallet.color.map { Color(hex: $0) } ?? .blue
    }

    var body: some View {
        HStack(spacing: 12) {
            icon
            titleSection
            Spacer()
            balanceSection
        }
        .padding(.vertical, 4)
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(accentColor.opacity(0.15))
                .frame(width: 44, height: 44)
            Text(wallet.displayIcon)
                .font(.system(size: 22))
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(wallet.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if wallet.isDefault {
                    StatusBadge(label: "Default", color: .blue)
                }
            }

            if wallet.type == "credit" {
                Text("Used: \(wallet.amountOwed.formatted(currency: "VND")) / \((wallet.creditLimit ?? 0).formatted(currency: "VND"))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text(wallet.typeLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var balanceSection: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(wallet.balance.formatted(currency: "VND"))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(balanceColor)

            if wallet.type == "credit" {
                Text("available")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var balanceColor: Color {
        if wallet.type == "credit" { return .income }
        return wallet.balance < 0 ? .red : .primary
    }
}
