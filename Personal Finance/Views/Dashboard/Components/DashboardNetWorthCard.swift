import SwiftUI

struct DashboardNetWorthCard: View {
    let netWorth: Double
    let cash: Double
    let lent: Double
    let borrowed: Double
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("NET WORTH")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1.5)

            Text(netWorth.formatted(currency: currency))
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(netWorth >= 0 ? Color.primary : Color.expense)

            pillsLayout
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder private var pillsLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                NetWorthPill(label: "Cash", value: cash, prefix: "", color: .primary, currency: currency)
                if lent > 0 {
                    NetWorthPill(label: "Lent", value: lent, prefix: "+", color: .income, currency: currency)
                }
            }
            if borrowed > 0 {
                NetWorthPill(label: "Borrowed", value: borrowed, prefix: "–", color: .expense, currency: currency)
            }
        }
    }
}

private struct NetWorthPill: View {
    let label: String
    let value: Double
    let prefix: String
    let color: Color
    let currency: String

    var body: some View {
        Text("\(label) \(prefix)\(value.formatted(currency: currency))")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(color == .primary ? Color(.tertiarySystemFill) : color.opacity(0.15))
            .clipShape(Capsule())
    }
}
