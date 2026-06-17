import SwiftUI

enum FilterType: String, CaseIterable {
    case all = "All", income = "Income", expense = "Expense"
}

struct TransactionHeaderSection: View {
    @Binding var selectedMonth: Date
    @Binding var selectedDate: Date?
    @Binding var filterType: FilterType
    let dailyData: [Date: (income: Double, expense: Double)]
    let income: Double
    let expense: Double

    var body: some View {
        Section {
            VStack(spacing: 10) {
                MonthCalendarView(
                    selectedMonth: $selectedMonth,
                    selectedDate: $selectedDate,
                    dailyData: dailyData
                )

                HStack(spacing: 8) {
                    TxStatBox(label: "Income",  amount: income,  color: .income)
                    TxStatBox(label: "Expense", amount: expense, color: .expense)
                    let net = income - expense
                    TxStatBox(label: "Net", amount: net, color: net >= 0 ? .income : .expense)
                }

                Picker("Filter", selection: $filterType) {
                    ForEach(FilterType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 30).onEnded { v in
                        let h = v.translation.width; let vert = v.translation.height
                        guard abs(h) > abs(vert) * 1.5, abs(h) > 40 else { return }
                        withAnimation(.easeInOut(duration: 0.2)) { cycleFilter(by: h < 0 ? 1 : -1) }
                    }
                )
            }
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowBackground(Color(.systemGroupedBackground))
        .listRowSeparator(.hidden)
    }

    private func cycleFilter(by delta: Int) {
        let cases = FilterType.allCases
        guard let idx = cases.firstIndex(of: filterType) else { return }
        filterType = cases[(idx + delta + cases.count) % cases.count]
    }
}
