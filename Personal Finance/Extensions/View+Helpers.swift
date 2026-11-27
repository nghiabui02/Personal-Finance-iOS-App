import SwiftUI
import UIKit

/// Haptic confirmation for money that actually moved.
///
/// Called imperatively because the sheets that record money dismiss themselves on
/// success, and a `.sensoryFeedback` on a view being dismissed never fires.
@MainActor
enum Haptics {
    static func moneyRecorded() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

extension View {
    /// Every failure in the app surfaces through here, so it also carries the error haptic.
    func errorAlert(_ errorMsg: Binding<String?>) -> some View {
        sensoryFeedback(.error, trigger: errorMsg.wrappedValue) { _, new in new != nil }
        .alert("Error", isPresented: Binding(
            get: { errorMsg.wrappedValue != nil },
            set: { if !$0 { errorMsg.wrappedValue = nil } }
        )) {
            Button("OK") { errorMsg.wrappedValue = nil }
        } message: {
            Text(errorMsg.wrappedValue ?? "")
        }
    }
}
