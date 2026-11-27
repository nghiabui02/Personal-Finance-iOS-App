import SwiftUI

struct BalanceCardView: View {
    let balance: Decimal
    let currency: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            Text("Total Balance")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))

            Text(balance.formatted(currency: currency))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .background(
            LinearGradient(colors: [.blue, .indigo],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
        )
        .clipShape(.rect(cornerRadius: 20))
        .padding(.horizontal)
        .shadow(color: .blue.opacity(colorScheme == .dark ? 0.5 : 0.25),
                radius: colorScheme == .dark ? 20 : 12,
                y: 6)
    }
}
