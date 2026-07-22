import SwiftUI

struct WalletRow: View {
    let wallet: LocalWallet
    let canTransfer: Bool
    let onTransfer: () -> Void
    let onEdit: () -> Void
    let onPayCredit: () -> Void
    let onNavigate: () -> Void

    private var accentColor: Color {
        wallet.color.map { Color(hex: $0) } ?? defaultColor
    }

    private var defaultColor: Color {
        switch wallet.type {
        case "bank":       return Color(red: 0.2, green: 0.7, blue: 0.4)
        case "e_wallet":   return Color(red: 0.1, green: 0.65, blue: 0.8)
        case "cash":       return Color(red: 0.8, green: 0.65, blue: 0.1)
        case "credit":     return Color(red: 0.55, green: 0.2, blue: 0.85)
        case "investment": return Color(red: 0.2, green: 0.5, blue: 0.9)
        default:           return Color(red: 0.3, green: 0.5, blue: 0.8)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: onNavigate) {
                VStack(alignment: .leading, spacing: 14) {
                    topRow
                    Text(wallet.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    balanceRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            actionButtons
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [accentColor, accentColor.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var topRow: some View {
        HStack {
            HStack(spacing: 8) {
                Text(wallet.displayIcon)
                    .font(.system(size: 20))
                Text(wallet.typeLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.2))
                    .clipShape(Capsule())
            }
            Spacer()
            if wallet.isDefault {
                Text("Default")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
    }

    @ViewBuilder
    private var balanceRow: some View {
        if wallet.type == "credit" {
            VStack(alignment: .leading, spacing: 2) {
                Text(wallet.amountOwed.formatted(currency: "VND"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("used of \((wallet.creditLimit ?? 0).formatted(currency: "VND"))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        } else {
            Text(wallet.balance.formatted(currency: "VND"))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            if canTransfer {
                cardButton("arrow.2.squarepath", title: "Transfer", action: onTransfer)
            }
            if wallet.type == "credit" {
                cardButton("creditcard.fill", title: "Pay Bill", action: onPayCredit)
            }
            cardButton("pencil", title: "Edit", action: onEdit)
        }
    }

    private func cardButton(_ icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.white.opacity(0.18))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
