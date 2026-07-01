import SwiftUI

struct DetailInfoRow: View {
    let title: String
    let value: String
    var valueColor: Color = .secondary

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }
}
