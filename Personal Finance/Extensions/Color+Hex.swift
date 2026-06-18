import SwiftUI
import UIKit

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b)
    }

    // Lighter variants in dark mode for better contrast on dark backgrounds
    static let income = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.290, green: 0.871, blue: 0.502, alpha: 1)
            : UIColor(red: 0.086, green: 0.639, blue: 0.290, alpha: 1)
    })
    static let expense = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.973, green: 0.443, blue: 0.443, alpha: 1)
            : UIColor(red: 0.863, green: 0.149, blue: 0.149, alpha: 1)
    })
    static let lend = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.376, green: 0.647, blue: 0.980, alpha: 1)
            : UIColor(red: 0.145, green: 0.388, blue: 0.922, alpha: 1)
    })
    static let borrow = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.984, green: 0.573, blue: 0.235, alpha: 1)
            : UIColor(red: 0.918, green: 0.345, blue: 0.047, alpha: 1)
    })
}

extension View {
    func cardBackground(cornerRadius: CGFloat = 12) -> some View {
        self
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
            }
    }
}
