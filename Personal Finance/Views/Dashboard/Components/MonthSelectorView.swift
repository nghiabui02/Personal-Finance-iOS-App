import SwiftUI

struct MonthSelectorView: View {
    @Binding var selectedMonth: Date

    @State private var showPicker = false

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

            Button { showPicker = true } label: {
                Text(selectedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                    .frame(minWidth: 160)
                    .foregroundColor(.primary)
            }

            Button { changeMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .fontWeight(.semibold)
                    .foregroundColor(isCurrentMonth ? .secondary : .primary)
            }
            .disabled(isCurrentMonth)
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showPicker) {
            MonthYearPickerSheet(selectedMonth: $selectedMonth, isPresented: $showPicker)
        }
    }

    private func changeMonth(by value: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: value, to: selectedMonth) {
            withAnimation { selectedMonth = next }
        }
    }
}

// MARK: - Month / Year Picker Sheet

private struct MonthYearPickerSheet: View {
    @Binding var selectedMonth: Date
    @Binding var isPresented: Bool

    @State private var pickerMonth: Int
    @State private var pickerYear: Int

    private let months = Calendar.current.monthSymbols
    private let years: [Int] = Array(2015...2035)

    init(selectedMonth: Binding<Date>, isPresented: Binding<Bool>) {
        self._selectedMonth = selectedMonth
        self._isPresented = isPresented
        let comps = Calendar.current.dateComponents([.year, .month], from: selectedMonth.wrappedValue)
        _pickerMonth = State(initialValue: (comps.month ?? 1) - 1)
        _pickerYear  = State(initialValue: comps.year ?? Calendar.current.component(.year, from: Date()))
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("Month", selection: $pickerMonth) {
                    ForEach(0..<months.count, id: \.self) { i in
                        Text(months[i]).tag(i)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)

                Picker("Year", selection: $pickerYear) {
                    ForEach(years, id: \.self) { y in
                        Text(String(y)).tag(y)
                    }
                }
                .pickerStyle(.wheel)
                .frame(width: 100)
            }
            .navigationTitle("Select Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        var comps = DateComponents()
                        comps.year = pickerYear
                        comps.month = pickerMonth + 1
                        comps.day = 1
                        if let date = Calendar.current.date(from: comps) {
                            withAnimation { selectedMonth = date }
                        }
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(280)])
    }
}
