import SwiftUI

struct DebtRow: View {
    let debt: LocalDebt
    var onPay: (() -> Void)? = nil
    var onAdd: (() -> Void)? = nil

    private var paidAmount: Decimal { debt.amount - debt.remainingAmount }
    private var progress: Double { debt.amount > 0 ? max(0, min(1, (paidAmount / debt.amount).doubleValue)) : 0 }
    private var accentColor: Color { debt.type == .lend ? .lend : .borrow }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            progressSection
            if debt.status != .completed, onPay != nil || onAdd != nil {
                actionButtons
            }
        }
        .padding(.vertical, 4)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if let onPay {
                Button(action: onPay) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                        Text(debt.type == .lend ? "Collect" : "Repay")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.borderless)
            }
            if let onAdd {
                Button(action: onAdd) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption2.weight(.bold))
                        Text(debt.type == .lend ? "Lend More" : "Borrow More")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.top, 2)
    }

    private var header: some View {
        HStack(spacing: 12) {
            icon

            VStack(alignment: .leading, spacing: 3) {
                Text(debt.personName)
                    .fontWeight(.medium)
                subtitle
            }

            Spacer()
            statusBadge
        }
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(accentColor.opacity(0.12))
                .frame(width: 44, height: 44)
            Image(systemName: debt.type == .lend ? "arrow.up.right" : "arrow.down.left")
                .foregroundStyle(accentColor)
                .font(.system(size: 18, weight: .semibold))
                .accessibilityHidden(true)
        }
    }

    private var subtitle: some View {
        HStack(spacing: 4) {
            Text(debt.type == .lend ? "Lent" : "Borrowed")
            if let dueDate = debt.dueDate {
                Text("·")
                Text("Due \(dueDate.formatted(.dateTime.month(.abbreviated).day()))")
                    .foregroundStyle(debt.status == .overdue ? .red : .secondary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var progressSection: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Paid \(paidAmount.formatted(currency: "VND"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(debt.remainingAmount.formatted(currency: "VND")) left")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(debt.status == .completed ? .secondary : .primary)
            }

            ProgressView(value: progress)
                .tint(accentColor)

            HStack {
                Spacer()
                Text("of \(debt.amount.formatted(currency: "VND"))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch debt.status {
        case .completed:
            StatusBadge(label: "Done", color: .green)
        case .overdue:
            StatusBadge(label: "Overdue", color: .red)
        case .active:
            StatusBadge(label: "Active", color: .blue)
        }
    }
}
