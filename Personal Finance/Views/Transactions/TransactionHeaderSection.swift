import SwiftUI

struct TransactionHeaderSection: View {
    @Binding var selectedMonth: Date
    @Binding var selectedDate: Date?
    @Binding var period: TransactionPeriodFilter
    @Binding var keyword: String
    let dailyData: [Date: (income: Double, expense: Double)]
    let income: Double
    let expense: Double
    let onAdd: () -> Void

    @State private var isSearching = false

    var body: some View {
        Section {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    TxStatBox(label: "Income",  amount: income,  color: .income)
                    TxStatBox(label: "Expense", amount: expense, color: .expense)
                    let net = income - expense
                    TxStatBox(label: "Net", amount: net, color: .indigo)
                }

                HStack(spacing: 10) {
                    Picker("Period", selection: $period) {
                        ForEach(TransactionPeriodFilter.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSearching.toggle()
                            if !isSearching { keyword = "" }
                        }
                    } label: {
                        Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 42, height: 42)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isSearching ? Color.accentColor : .secondary)
                    .accessibilityLabel(isSearching ? "Close search" : "Search transactions")

                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 42)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add transaction")
                }

                if isSearching {
                    searchField
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                MonthCalendarView(
                    selectedMonth: $selectedMonth,
                    selectedDate: $selectedDate,
                    dailyData: dailyData
                )
            }
            .padding(.vertical, 8)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowBackground(Color(.systemGroupedBackground))
        .listRowSeparator(.hidden)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search note, category or wallet", text: $keyword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !keyword.isEmpty {
                Button {
                    keyword = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
