import SwiftUI

struct ReportPeriodSelectorView: View {
    @Binding var selectedPeriod: ReportPeriod
    let animation: Namespace.ID

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ReportPeriod.allCases) { period in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedPeriod = period
                    }
                } label: {
                    Text(period.rawValue)
                        .font(.subheadline.weight(selectedPeriod == period ? .semibold : .regular))
                        .foregroundColor(selectedPeriod == period ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selectionBackground(for: period))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func selectionBackground(for period: ReportPeriod) -> some View {
        if selectedPeriod == period {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.tertiarySystemGroupedBackground))
                .matchedGeometryEffect(id: "periodTab", in: animation)
        }
    }
}
