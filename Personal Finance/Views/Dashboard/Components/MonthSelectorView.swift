import SwiftUI

struct MonthSelectorView: View {
    @Binding var selectedMonth: Date

    private var title: String {
        selectedMonth.formatted(.dateTime.month(.wide).year())
    }

    private var isCurrentMonth: Bool {
        Calendar.current.isDate(selectedMonth, equalTo: Date(), toGranularity: .month)
    }

    var body: some View {
        HStack(spacing: 16) {
            Button { changeMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }

            Text(title)
                .font(.headline)
                .frame(minWidth: 160)
                .onTapGesture { withAnimation { selectedMonth = Date() } }

            Button { changeMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .fontWeight(.semibold)
                    .foregroundColor(isCurrentMonth ? .secondary : .primary)
            }
            .disabled(isCurrentMonth)
        }
        .padding(.vertical, 8)
    }

    private func changeMonth(by value: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: value, to: selectedMonth) {
            withAnimation { selectedMonth = next }
        }
    }
}
