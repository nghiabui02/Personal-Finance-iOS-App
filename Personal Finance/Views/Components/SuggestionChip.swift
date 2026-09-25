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
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
