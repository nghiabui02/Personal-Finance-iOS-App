import SwiftUI

struct MonthlyStatView: View {
    let title: String
    let amount: Double
    let color: Color
    let icon: String
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundColor(color)
                Text(title).font(.subheadline).foregroundColor(.secondary)
            }
            Text(amount.formatted(currency: currency))
                .font(.system(.title3, design: .rounded))
                .fontWeight(.semibold)
                .foregroundColor(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}
