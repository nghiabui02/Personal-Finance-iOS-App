import SwiftUI

struct SettingsRow: View {
    let icon: String
    let color: Color
    let title: LocalizedStringKey
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                iconView
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var iconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(color)
                .frame(width: 30, height: 30)
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .accessibilityHidden(true)
                .foregroundStyle(.white)
        }
    }
}
