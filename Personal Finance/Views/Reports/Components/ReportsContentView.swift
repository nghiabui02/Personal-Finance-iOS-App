import SwiftUI

struct ReportsContentView: View {
    @Binding var selectedPeriod: ReportPeriod

    let metrics: ReportMetrics
    let rangeLabel: String
    let isCurrentPeriod: Bool
    let onNavigatePeriod: (Int) -> Void

    @Namespace private var periodAnimation

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ReportPeriodSelectorView(selectedPeriod: $selectedPeriod, animation: periodAnimation)
                    .padding(.horizontal)

                ReportDateNavigatorView(
                    rangeLabel: rangeLabel,
                    isCurrentPeriod: isCurrentPeriod,
                    onPrevious: { onNavigatePeriod(-1) },
                    onNext: { onNavigatePeriod(1) }
                )
                .padding(.horizontal)

                ReportCashFlowCard(metrics: metrics)
                    .padding(.horizontal)

                ReportIncomeExpenseChartCard(period: selectedPeriod, data: metrics.chartData)
                    .padding(.horizontal)

                if !metrics.spendingBreakdown.isEmpty {
                    ReportSpendingBreakdownCard(items: metrics.spendingBreakdown)
                        .padding(.horizontal)
                }

                ReportNetWorthCard(
                    amount: metrics.currentNetWorth,
                    cash: metrics.cash,
                    lent: metrics.lent,
                    creditOwed: metrics.creditOwed,
                    borrowed: metrics.borrowed,
                    history: metrics.netWorthHistory
                )
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
    }
}
