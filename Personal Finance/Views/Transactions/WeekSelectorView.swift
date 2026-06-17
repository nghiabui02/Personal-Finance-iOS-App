import SwiftUI

struct WeekSelectorView: View {
    @Binding var weekStart: Date

    private var cal: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }
    private var weekEnd: Date { cal.date(byAdding: .day, value: 6, to: weekStart)! }

    private var isCurrentWeek: Bool {
        cal.isDate(weekStart, equalTo: Date(), toGranularity: .weekOfYear)
    }

    private var label: String {
        let s = weekStart.formatted(.dateTime.day().month(.abbreviated))
        let e = weekEnd.formatted(.dateTime.day().month(.abbreviated).year())
        return "\(s) – \(e)"
    }

    var body: some View {
        HStack(spacing: 16) {
            Button { change(by: -1) } label: {
                Image(systemName: "chevron.left").fontWeight(.semibold).foregroundColor(.primary)
            }
            Text(label).font(.headline).frame(minWidth: 180)
                .onTapGesture {
                    var c = Calendar.current; c.firstWeekday = 2
                    let comps = c.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
                    withAnimation { weekStart = c.date(from: comps) ?? Date() }
                }
            Button { change(by: 1) } label: {
                Image(systemName: "chevron.right").fontWeight(.semibold)
                    .foregroundColor(isCurrentWeek ? .secondary : .primary)
            }
            .disabled(isCurrentWeek)
        }
        .padding(.vertical, 8)
    }

    private func change(by weeks: Int) {
        if let next = cal.date(byAdding: .weekOfYear, value: weeks, to: weekStart) {
            withAnimation { weekStart = next }
        }
    }
}
