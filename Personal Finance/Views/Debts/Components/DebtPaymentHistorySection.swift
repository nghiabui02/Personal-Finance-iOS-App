import SwiftUI

struct DebtPaymentHistorySection: View {
    let payments: [RemoteDebtPayment]
    let isLoading: Bool
    let errorMessage: String?

    var body: some View {
        Section("History") {
            if isLoading && payments.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let errorMessage, payments.isEmpty {
                ContentUnavailableView(
                    "Could Not Load History",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                .padding(.vertical)
            } else if payments.isEmpty {
                ContentUnavailableView(
                    "No Payment History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Payments and additions appear here.")
                )
                .padding(.vertical)
            } else {
                ForEach(payments) { payment in
                    DebtPaymentHistoryRow(payment: payment)
                }
            }
        }
    }
}

private struct DebtPaymentHistoryRow: View {
    let payment: RemoteDebtPayment

    private var isAddition: Bool {
        payment.type == "addition"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isAddition ? "plus.circle.fill" : "checkmark.circle.fill")
                .font(.title3)
                .foregroundColor(isAddition ? .orange : .green)

            VStack(alignment: .leading, spacing: 3) {
                Text(isAddition ? "Amount Added" : "Payment")
                    .font(.subheadline.weight(.medium))
                paymentMetadata
            }

            Spacer()

            Text("\(isAddition ? "+" : "-")\(payment.amount.formatted(currency: "VND"))")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(isAddition ? .orange : .green)
        }
        .padding(.vertical, 4)
    }

    private var paymentMetadata: some View {
        HStack(spacing: 4) {
            Text(payment.paidAt.formatted(date: .abbreviated, time: .omitted))
            if let note = payment.note, !note.isEmpty {
                Text("·")
                Text(note).lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }
}
