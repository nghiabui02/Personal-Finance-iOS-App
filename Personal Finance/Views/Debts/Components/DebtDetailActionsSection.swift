import SwiftUI

struct DebtDetailActionsSection: View {
    let debt: LocalDebt
    let onRecordPayment: () -> Void
    let onAddAmount: () -> Void

    var body: some View {
        Section {
            Button(action: onRecordPayment) {
                Label(
                    debt.type == "lend" ? "Record Collection" : "Record Payment",
                    systemImage: "checkmark.circle"
                )
            }
            .disabled(debt.remainingAmount <= 0)

            Button(action: onAddAmount) {
                Label("Add Amount", systemImage: "plus.circle")
            }
        }
    }
}
