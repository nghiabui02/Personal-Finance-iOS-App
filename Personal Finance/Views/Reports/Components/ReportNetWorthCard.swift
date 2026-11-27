import Charts
import SwiftUI

struct ReportNetWorthCard: View {
    let amount: Decimal
    let cash: Decimal
    let lent: Decimal
    let creditOwed: Decimal
    let borrowed: Decimal
    let history: [NetWorthPoint]

    @State private var selectedPoint: NetWorthPoint?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            netWorthSummary
            if !history.isEmpty {
                Divider()
                netWorthChart
            } else {
                Text("No net worth snapshots available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
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

            Chart {
                ForEach(history) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", (point.value / 1_000_000).doubleValue)
                    )
                    .foregroundStyle(Color.blue)
                    .accessibilityHidden(true)

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Value", (point.value / 1_000_000).doubleValue)
                    )
                    .foregroundStyle(Color.blue)
                    .symbolSize(14)
                    .accessibilityLabel(point.label)
                    .accessibilityValue(point.value.formatted(currency: "VND"))

                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Base", 0.0),
                        yEnd: .value("Value", (point.value / 1_000_000).doubleValue)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue.opacity(0.3), .blue.opacity(0.03)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .accessibilityHidden(true)
                }

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
                            Text(date, format: LedgerDate.display(.dateTime.day().month()))
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
                            Text(compactAmount(v * 1_000_000))
                                .font(.caption2)
                        }
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard let plotFrame = proxy.plotFrame else { return }
                                    let originX = geo[plotFrame].origin.x
                                    let x = value.location.x - originX
                                    let positioned = history.compactMap { point -> (NetWorthPoint, CGFloat)? in
                                        guard let px = proxy.position(forX: point.date) else { return nil }
                                        return (point, px)
                                    }
                                    if let nearest = positioned.min(by: { abs($0.1 - x) < abs($1.1 - x) }) {
                                        selectedPoint = nearest.0
                                    }
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

}

private struct NWPill: View {
    let label: LocalizedStringKey
    let value: Decimal
    var prefix: String = ""
    let color: Color

    var body: some View {
        Text("\(Text(label)) \(prefix)\(value.formatted(currency: "VND"))")
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
