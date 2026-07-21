import SwiftUI

struct WalletSummaryCard: View {
    let totalBalance: Double
    let walletCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TOTAL BALANCE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.65))
                .tracking(1.2)

            Text(totalBalance.formatted(currency: "VND"))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text("\(walletCount) wallet\(walletCount == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.20),
                    Color(red: 0.12, green: 0.15, blue: 0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
