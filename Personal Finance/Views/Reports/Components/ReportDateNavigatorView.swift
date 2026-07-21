import SwiftUI

struct ReportDateNavigatorView: View {
    let rangeLabel: String
    let isCurrentPeriod: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onPrevious) {
                navigationIcon("chevron.left", color: .secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(rangeLabel)
                .font(.subheadline.weight(.medium))

            Spacer()

            Button(action: onNext) {
                navigationIcon(
                    "chevron.right",
                    color: isCurrentPeriod ? Color.secondary.opacity(0.3) : .secondary
                )
            }
            .buttonStyle(.plain)
            .disabled(isCurrentPeriod)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func navigationIcon(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .frame(width: 44, height: 36)
            .contentShape(Rectangle())
    }
}
