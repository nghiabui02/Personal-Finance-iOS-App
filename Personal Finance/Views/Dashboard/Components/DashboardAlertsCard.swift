import SwiftUI

struct DashboardAlert: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let message: String
    let symbol: String
    let color: Color
    let priority: Int
}

struct DashboardAlertsCard: View {
    let alerts: [DashboardAlert]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ALERTS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1)

            ForEach(alerts) { alert in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: alert.symbol)
                        .foregroundStyle(alert.color)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.title).font(.subheadline.weight(.semibold))
                        Text(alert.message).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
