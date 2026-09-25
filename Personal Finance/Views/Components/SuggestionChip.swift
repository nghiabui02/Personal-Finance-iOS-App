import SwiftUI

/// Tappable capsule used by the one-tap suggestion rows (amount shortcuts,
/// frequent transactions). Optional leading emoji, then a label.
struct SuggestionChip: View {
    var icon: String? = nil
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Text(icon) }
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            // Tinted rather than grey: a chip sits on a form row, whose background is
            // already `secondarySystemGroupedBackground` — a grey fill would vanish into it.
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
