import SwiftUI

struct ReportSpendingBreakdownCard: View {
    let items: [ReportCategoryBreakdown]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SPENDING BREAKDOWN")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .tracking(1)

            ForEach(items) { item in
                ReportSpendingBreakdownRow(item: item)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct ReportSpendingBreakdownRow: View {
    let item: ReportCategoryBreakdown

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                categoryIcon
                Text(item.name)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.0f%%", item.percentage))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .trailing)
                Text(item.amount.formatted(currency: "VND"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(.systemFill))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(item.color)
                        .frame(
                            width: max(0, geometry.size.width * (item.percentage / 100)),
                            height: 4
                        )
                }
            }
            .frame(height: 4)
        }
    }

    private var categoryIcon: some View {
        ZStack {
            Circle()
                .fill(item.color.opacity(0.15))
                .frame(width: 36, height: 36)
            Text(item.icon)
                .font(.system(size: 18))
        }
    }
}
