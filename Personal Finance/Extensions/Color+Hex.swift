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

    static let income  = Color(hex: "#22c55e")
    static let expense = Color(hex: "#ef4444")
    static let lend    = Color(hex: "#3b82f6")
    static let borrow  = Color(hex: "#f97316")
}

// MARK: - View utilities

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

    /// scrollDismissesKeyboard + keyboard toolbar Done button.
    /// UIKit (resignFirstResponder) is unavoidable for global keyboard dismissal —
    /// SwiftUI has no equivalent API.
    func formKeyboardHandling() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                }
            }
    }
}

// Global helper so any file can dismiss keyboard without importing UIKit.
func hideKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil, from: nil, for: nil
    )
}
