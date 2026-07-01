import SwiftUI

struct WalletDetailHeader: View {
    let wallet: LocalWallet

    private var accentColor: Color {
        wallet.color.map { Color(hex: $0) } ?? .blue
    }

    private var creditUtilization: Double {
        guard let limit = wallet.creditLimit, limit > 0 else { return 0 }
        return min(wallet.amountOwed / limit, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            identitySection

            if wallet.type == "credit" {
                creditSummary
            } else {
                balanceSummary
            }
        }
        .padding(.vertical, 8)
    }

    private var identitySection: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 52, height: 52)
                Text(wallet.displayIcon).font(.system(size: 26))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(wallet.name).font(.headline)
                Text(wallet.typeLabel).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if wallet.isDefault {
                StatusBadge(label: "Default", color: .blue)
            }
        }
    }

    private var balanceSummary: some View {
        Text(wallet.balance.formatted(currency: "VND"))
            .font(.system(.largeTitle, design: .rounded).weight(.bold))
            .foregroundColor(wallet.balance >= 0 ? .primary : .expense)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
    }

    private var creditSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                valueColumn(
                    title: "AVAILABLE",
                    value: wallet.balance.formatted(currency: "VND"),
                    color: .income
                )
                Spacer()
                valueColumn(
                    title: "OUTSTANDING",
                    value: wallet.amountOwed.formatted(currency: "VND"),
                    color: .expense,
                    alignment: .trailing
                )
            }
            ProgressView(value: creditUtilization)
                .tint(creditUtilization >= 0.8 ? .expense : accentColor)
            Text("Limit: \((wallet.creditLimit ?? 0).formatted(currency: "VND"))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func valueColumn(
        title: String,
        value: String,
        color: Color,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundColor(color)
        }
    }
}
