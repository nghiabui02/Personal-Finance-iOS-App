import SwiftUI

struct BalanceCardView: View {
    let balance: Double
    let currency: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            Text("Total Balance")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))

            Text(balance.formatted(currency: currency))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.white)
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
        .cornerRadius(20)
        .padding(.horizontal)
        .shadow(color: .blue.opacity(colorScheme == .dark ? 0.5 : 0.25),
                radius: colorScheme == .dark ? 20 : 12,
                y: 6)
    }
}
