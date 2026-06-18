import SwiftUI

struct TxStatBox: View {
    let label: String
    let amount: Double
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(amount.formatted(currency: "VND"))
                .font(.caption.weight(.bold))
                .foregroundColor(color)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(color.opacity(colorScheme == .dark ? 0.15 : 0.08))
        .cornerRadius(10)
    }
}
