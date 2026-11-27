import SwiftUI

struct MonthlyStatView: View {
    let title: LocalizedStringKey
    let amount: Decimal
    let color: Color
    let icon: String
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(amount.formatted(currency: currency))
                .font(.system(.title3, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: 12))
    }
}
