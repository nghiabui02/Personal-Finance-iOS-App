import SwiftUI

struct ReportNetWorthCard: View {
    let amount: Double

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("CURRENT NET WORTH")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .tracking(1)
                Text(amount.formatted(currency: "VND"))
                    .font(.title2.weight(.bold))
                    .foregroundColor(amount >= 0 ? .primary : .expense)
            }
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title2)
                .foregroundColor(.blue)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
