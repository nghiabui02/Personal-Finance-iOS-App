import SwiftUI

struct DebtInformationSection: View {
    let debt: LocalDebt
    let linkedWallet: LocalWallet?

    var body: some View {
        Section("Details") {
            DetailInfoRow(
                title: "Type",
                value: debt.type == .lend ? "I Lent" : "I Borrowed"
            )
            DetailInfoRow(
                title: "Status",
                value: AppLocalization.shared.language.text(debt.status.rawValue.capitalized),
                valueColor: statusColor
            )
            if let dueDate = debt.dueDate {
                DetailInfoRow(
                    title: "Due Date",
                    value: dueDate.formatted(LedgerDate.display(.dateTime.day().month(.abbreviated).year())),
                    valueColor: isOverdue ? .expense : .secondary
                )
            }
            if let contact = debt.personContact, !contact.isEmpty {
                DetailInfoRow(title: "Contact", value: contact)
            }
            if let linkedWallet {
                DetailInfoRow(
                    title: "Wallet",
                    value: "\(linkedWallet.displayIcon) \(linkedWallet.name)"
                )
            }
            if let note = debt.note, !note.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Note").font(.caption).foregroundStyle(.secondary)
                    Text(note)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var statusColor: Color {
        switch debt.status {
        case .completed: return .green
        case .overdue: return .expense
        case .active: return .blue
        }
    }

    private var isOverdue: Bool {
        guard let dueDate = debt.dueDate else { return false }
        return LedgerDate.calendar.startOfDay(for: dueDate)
            < LedgerDate.calendar.startOfDay(for: Date())
            && debt.status != .completed
    }
}
