import SwiftUI

struct StatusBadge: View {
    let label: LocalizedStringKey
    let color: Color

    var body: some View {
        Text(label)
            .font(.caption2).fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(.rect(cornerRadius: 4))
    }
}
