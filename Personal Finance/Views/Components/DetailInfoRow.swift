import SwiftUI

struct DetailInfoRow: View {
    let title: LocalizedStringKey
    let value: String
    var valueColor: Color = .secondary

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }
}
