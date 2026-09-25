import SwiftUI

struct MonthCalendarView: View {
    @Binding var selectedMonth: Date
    @Binding var selectedDate: Date?
    let dailyData: [Date: (income: Double, expense: Double)]

    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdaySymbols = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private var firstDayOfMonth: Date {
        cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth))!
    }

    private var daysInMonth: Int {
        cal.range(of: .day, in: .month, for: selectedMonth)!.count
    }

    // Offset so week starts on Monday (Sun=1→6, Mon=2→0, ..., Sat=7→5)
    private var startOffset: Int {
        let weekday = cal.component(.weekday, from: firstDayOfMonth)
        return (weekday - 2 + 7) % 7
    }

    private var today: Date { cal.startOfDay(for: Date()) }

    private var nextDisabled: Bool {
        let current = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        return selectedMonth >= current
    }

    private struct GridCell: Identifiable {
        let id: String
        let day: Int?
        let date: Date?
    }

    private var gridCells: [GridCell] {
        var cells: [GridCell] = (0..<startOffset).map { GridCell(id: "e\($0)", day: nil, date: nil) }
        for day in 1...daysInMonth {
            let date = cal.date(byAdding: .day, value: day - 1, to: firstDayOfMonth)!
            cells.append(GridCell(id: "d\(day)", day: day, date: date))
        }
        return cells
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture { changeMonth(by: -1) }

                Spacer()
                Text(selectedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline.weight(.bold))
                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(nextDisabled ? Color.secondary.opacity(0.25) : .secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture { if !nextDisabled { changeMonth(by: 1) } }
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .padding(.bottom, 4)

            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { sym in
                    Text(sym)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(gridCells) { cell in
                    if let day = cell.day, let date = cell.date {
                        let isToday    = date == today
                        let isSelected = selectedDate.map { cal.isDate($0, inSameDayAs: date) } ?? false
                        CalendarDayCell(
                            day: day, date: date,
                            isToday: isToday, isSelected: isSelected,
                            data: dailyData[date]
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedDate = isSelected ? nil : date
                            }
                        }
                    } else {
                        Color.clear.frame(height: 46)
                    }
                }
            }
            .padding(.bottom, 10)
        }
        .padding(.horizontal, 8)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator).opacity(0.4), lineWidth: 0.75)
        }
    }

    private func changeMonth(by delta: Int) {
        if let next = cal.date(byAdding: .month, value: delta, to: selectedMonth) {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedMonth = next
                selectedDate = nil
            }
        }
    }
}

private struct CalendarDayCell: View {
    let day: Int
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let data: (income: Double, expense: Double)?
    let onTap: () -> Void

    private var net: Double? {
        guard let d = data else { return nil }
        let n = d.income - d.expense
        return n == 0 ? nil : n
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 1) {
                ZStack {
                    if isToday {
                        Circle().fill(Color.blue).frame(width: 30, height: 30)
                    } else if isSelected {
                        Circle().fill(Color(.label)).frame(width: 30, height: 30)
                    }
                    Text("\(day)")
                        .font(.subheadline)
                        .foregroundColor(isToday ? .white : isSelected ? Color(.systemBackground) : .primary)
                }
                .frame(height: 30)

                if let n = net {
                    Text(compactNet(n))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(n > 0 ? .income : .expense)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else {
                    Color.clear.frame(height: 11)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func compactNet(_ n: Double) -> String {
        let abs = Swift.abs(n)
        let sign = n > 0 ? "+" : "-"
        if abs >= 1_000_000_000 {
            return "\(sign)\(String(format: "%.1f", abs / 1_000_000_000))B"
        } else if abs >= 1_000_000 {
            return "\(sign)\(Int(abs / 1_000_000))M"
        } else if abs >= 1_000 {
            return "\(sign)\(Int(abs / 1_000))k"
        }
        return "\(sign)\(Int(abs))"
    }
}
