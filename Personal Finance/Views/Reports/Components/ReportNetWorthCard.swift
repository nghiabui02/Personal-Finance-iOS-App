import Charts
import SwiftUI

struct ReportNetWorthCard: View {
    let amount: Double
    let cash: Double
    let lent: Double
    let creditOwed: Double
    let borrowed: Double
    let history: [NetWorthPoint]

    @State private var selectedPoint: NetWorthPoint?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            netWorthSummary
            if !history.isEmpty {
                Divider()
                netWorthChart
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var netWorthSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NET WORTH")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)

            Text(amount.formatted(currency: "VND"))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(amount >= 0 ? Color.primary : Color.expense)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            pillGrid
        }
    }

    private var pillGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                NWPill(label: "Cash", value: cash, color: .primary)
                if lent > 0 {
                    NWPill(label: "Lent", value: lent, prefix: "+", color: .income)
                }
            }
            HStack(spacing: 8) {
                if creditOwed > 0 {
                    NWPill(label: "Credit", value: -creditOwed, color: .expense)
                }
                if borrowed > 0 {
                    NWPill(label: "Borrowed", value: -borrowed, color: .expense)
                }
            }
        }
    }

    private var netWorthChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Net Worth")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let sel = selectedPoint {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(sel.value.formatted(currency: "VND"))
                            .font(.caption.weight(.semibold))
                        Text(sel.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: selectedPoint?.id)

            Chart(history) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value / 1_000_000)
                )
                .foregroundStyle(Color.blue)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Base", 0.0),
                    yEnd: .value("Value", point.value / 1_000_000)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue.opacity(0.3), .blue.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                if let sel = selectedPoint {
                    RuleMark(x: .value("Selected", sel.date))
                        .foregroundStyle(Color.primary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.day().month())
                                .font(.caption2)
                        }
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(compactLabel(v))
                                .font(.caption2)
                        }
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                }
            }
            .chartOverlay { proxy in
                GeometryReader { _ in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let x = value.location.x
                                    selectedPoint = history.min(by: {
                                        abs((proxy.position(forX: $0.date) ?? 0) - x) <
                                        abs((proxy.position(forX: $1.date) ?? 0) - x)
                                    })
                                }
                                .onEnded { _ in
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        selectedPoint = nil
                                    }
                                }
                        )
                }
            }
            .frame(height: 160)
        }
    }

    private var chartMinValue: Double {
        (history.map { $0.value }.min() ?? 0) * 0.95
    }

    private func compactLabel(_ millionValue: Double) -> String {
        if millionValue == 0 { return "0" }
        if abs(millionValue) >= 1000 { return "\(Int(millionValue / 1000))B" }
        return "\(Int(millionValue))M"
    }
}

private struct NWPill: View {
    let label: String
    let value: Double
    var prefix: String = ""
    let color: Color

    var body: some View {
        Text("\(label) \(prefix)\(value.formatted(currency: "VND"))")
            .font(.caption.weight(.medium))
            .foregroundStyle(color == .primary ? .primary : color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                color == .primary
                    ? Color(.tertiarySystemFill)
                    : color.opacity(0.15)
            )
            .clipShape(Capsule())
    }
}
