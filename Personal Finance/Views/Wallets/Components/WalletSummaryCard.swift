import SwiftUI

struct WalletSummaryCard: View {
    let netWorth: Double

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Net Worth")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(netWorth.formatted(currency: "VND"))
                    .font(.system(.title2, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(netWorth >= 0 ? .primary : .red)
            }

            Spacer()

            Image(systemName: "creditcard.fill")
                .font(.title2)
                .foregroundColor(.blue)
        }
        .padding(.vertical, 4)
    }
}
