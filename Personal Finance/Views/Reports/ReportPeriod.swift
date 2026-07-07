import Foundation

enum ReportPeriod: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case quarter = "Quarter"
    case year = "Year"

    var id: String { rawValue }
}

struct ReportPeriodContext {
    let period: ReportPeriod
    let referenceDate: Date
    let calendar: Calendar

    init(
        period: ReportPeriod,
        referenceDate: Date,
        calendar: Calendar = .current
    ) {
        self.period = period
        self.referenceDate = referenceDate
        self.calendar = calendar
    }

    var range: (start: Date, end: Date) {
        switch period {
        case .week:
            let weekday = calendar.component(.weekday, from: referenceDate)
            let daysFromMonday = (weekday - 2 + 7) % 7
            let monday = calendar.date(
                byAdding: .day,
                value: -daysFromMonday,
                to: calendar.startOfDay(for: referenceDate)
            ) ?? referenceDate
            let sunday = calendar.date(byAdding: .day, value: 6, to: monday) ?? monday
            return (monday, sunday)
        case .month:
            let start = calendar.date(
                from: calendar.dateComponents([.year, .month], from: referenceDate)
            ) ?? referenceDate
            let dayCount = calendar.range(of: .day, in: .month, for: referenceDate)?.count ?? 1
            let end = calendar.date(byAdding: .day, value: dayCount - 1, to: start) ?? start
            return (start, end)
        case .quarter:
            let month = calendar.component(.month, from: referenceDate)
            var components = calendar.dateComponents([.year], from: referenceDate)
            components.month = ((month - 1) / 3) * 3 + 1
            components.day = 1
            let start = calendar.date(from: components) ?? referenceDate
            let end = calendar.date(
                byAdding: .day,
                value: -1,
                to: calendar.date(byAdding: .month, value: 3, to: start) ?? start
            ) ?? start
            return (start, end)
        case .year:
            var startComponents = calendar.dateComponents([.year], from: referenceDate)
            startComponents.month = 1
            startComponents.day = 1
            let start = calendar.date(from: startComponents) ?? referenceDate

            var endComponents = calendar.dateComponents([.year], from: referenceDate)
            endComponents.month = 12
            endComponents.day = 31
            let end = calendar.date(from: endComponents) ?? start
            return (start, end)
        }
    }

    var rangeLabel: String {
        switch period {
        case .week:
            let range = range
            return "\(range.start.formatted(.dateTime.month(.abbreviated).day())) – \(range.end.formatted(.dateTime.month(.abbreviated).day())), \(calendar.component(.year, from: range.end))"
        case .month:
            return referenceDate.formatted(.dateTime.month(.wide).year())
        case .quarter:
            let quarter = (calendar.component(.month, from: range.start) - 1) / 3 + 1
            return "Q\(quarter) \(calendar.component(.year, from: referenceDate))"
        case .year:
            return String(calendar.component(.year, from: referenceDate))
        }
    }

    var isCurrent: Bool {
        let now = Date()
        switch period {
        case .week:
            return calendar.isDate(referenceDate, equalTo: now, toGranularity: .weekOfYear)
        case .month:
            return calendar.isDate(referenceDate, equalTo: now, toGranularity: .month)
        case .quarter:
            let referenceQuarter = (calendar.component(.month, from: referenceDate) - 1) / 3
            let currentQuarter = (calendar.component(.month, from: now) - 1) / 3
            return calendar.component(.year, from: referenceDate) == calendar.component(.year, from: now)
                && referenceQuarter == currentQuarter
        case .year:
            return calendar.isDate(referenceDate, equalTo: now, toGranularity: .year)
        }
    }

    func date(byAdding delta: Int) -> Date? {
        switch period {
        case .week:
            return calendar.date(byAdding: .weekOfYear, value: delta, to: referenceDate)
        case .month:
            return calendar.date(byAdding: .month, value: delta, to: referenceDate)
        case .quarter:
            return calendar.date(byAdding: .month, value: delta * 3, to: referenceDate)
        case .year:
            return calendar.date(byAdding: .year, value: delta, to: referenceDate)
        }
    }
}
