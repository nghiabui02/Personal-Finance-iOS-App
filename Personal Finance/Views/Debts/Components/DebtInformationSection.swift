import SwiftUI

struct DebtInformationSection: View {
    let debt: LocalDebt
    let linkedWallet: LocalWallet?

    var body: some View {
        Section("Details") {
            DetailInfoRow(
                title: "Type",
                value: debt.type == "lend" ? "I Lent" : "I Borrowed"
            )
            DetailInfoRow(
                title: "Status",
                value: debt.status.capitalized,
                valueColor: statusColor
            )
            if let dueDate = debt.dueDate {
                DetailInfoRow(
                    title: "Due Date",
                    value: dueDate.formatted(date: .abbreviated, time: .omitted),
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
                    Text("Note").font(.caption).foregroundColor(.secondary)
                    Text(note)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var statusColor: Color {
        switch debt.status {
        case "completed": return .green
        case "overdue": return .expense
        default: return .blue
        }
    }

    private var isOverdue: Bool {
        guard let dueDate = debt.dueDate else { return false }
        return Calendar.current.startOfDay(for: dueDate)
            < Calendar.current.startOfDay(for: Date())
            && debt.status != "completed"
    }
}
