import SwiftUI

extension View {
    func errorAlert(_ errorMsg: Binding<String?>) -> some View {
        alert("Error", isPresented: Binding(
            get: { errorMsg.wrappedValue != nil },
            set: { if !$0 { errorMsg.wrappedValue = nil } }
        )) {
            Button("OK") { errorMsg.wrappedValue = nil }
        } message: {
            Text(errorMsg.wrappedValue ?? "")
        }
    }
}
