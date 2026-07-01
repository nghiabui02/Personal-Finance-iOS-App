import SwiftUI

struct DashboardNetWorthCard: View {
    let netWorth: Double
    let lent: Double
    let borrowed: Double
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NET WORTH")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .tracking(1)
            Text(netWorth.formatted(currency: currency))
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundColor(netWorth >= 0 ? .primary : .expense)
            HStack {
                Label(lent.formatted(currency: currency), systemImage: "arrow.up.right")
                    .foregroundColor(.lend)
                Spacer()
                Label(borrowed.formatted(currency: currency), systemImage: "arrow.down.left")
                    .foregroundColor(.borrow)
            }
            .font(.caption.weight(.medium))
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
