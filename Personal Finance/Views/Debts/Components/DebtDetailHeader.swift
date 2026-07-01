import SwiftUI

struct DebtDetailHeader: View {
    let debt: LocalDebt

    private var paidAmount: Double {
        max(0, debt.amount - debt.remainingAmount)
    }

    private var progress: Double {
        debt.amount > 0 ? min(paidAmount / debt.amount, 1) : 0
    }

    private var accentColor: Color {
        debt.type == "lend" ? .lend : .borrow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(debt.type == "lend" ? "RECEIVABLE" : "PAYABLE")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .tracking(1)
                    Text(debt.remainingAmount.formatted(currency: "VND"))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundColor(accentColor)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: debt.type == "lend" ? "arrow.up.right" : "arrow.down.left")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(accentColor)
            }

            ProgressView(value: progress)
                .tint(accentColor)

            HStack {
                Text("Paid \(paidAmount.formatted(currency: "VND"))")
                Spacer()
                Text("Original \(debt.amount.formatted(currency: "VND"))")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}
