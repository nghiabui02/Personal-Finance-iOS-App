import SwiftUI
import SwiftData

struct DebtsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalDebt.personName) private var allDebts: [LocalDebt]
    @Query(sort: \LocalWallet.name) private var wallets: [LocalWallet]

    @State private var showAdd = false
    @State private var editing: LocalDebt?
    @State private var payingDebt: LocalDebt?
    @State private var filterType: FilterType = .all
    @State private var errorMsg: String?

    enum FilterType: String, CaseIterable { case all = "All", lend = "I Lend", borrow = "I Borrow" }

    private var filtered: [LocalDebt] {
        switch filterType {
        case .all: return allDebts
        case .lend: return allDebts.filter { $0.type == "lend" }
        case .borrow: return allDebts.filter { $0.type == "borrow" }
        }
    }

    private var active: [LocalDebt] { filtered.filter { $0.status == "active" || $0.status == "overdue" } }
    private var completed: [LocalDebt] { filtered.filter { $0.status == "completed" } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filter", selection: $filterType) {
                    ForEach(FilterType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))

                if filtered.isEmpty {
                    ContentUnavailableView("No Debts", systemImage: "dollarsign.circle",
                        description: Text("Tap + to add a debt record"))
                        .frame(maxHeight: .infinity)
                } else {
                    List {
                        if !active.isEmpty {
                            Section("Active") {
                                ForEach(active, id: \.serverId) { debt in
                                    DebtRow(debt: debt)
                                        .onTapGesture { editing = debt }
                                        .swipeActions(edge: .leading) {
                                            Button {
                                                payingDebt = debt
                                            } label: { Label("Pay", systemImage: "checkmark.circle") }
                                            .tint(.green)
                                        }
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                Task { await delete(debt) }
                                            } label: { Label("Delete", systemImage: "trash") }
                                        }
                                }
                            }
                        }
                        if !completed.isEmpty {
                            Section("Completed") {
                                ForEach(completed, id: \.serverId) { debt in
                                    DebtRow(debt: debt)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Debts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { AddEditDebtView(debt: nil) }
            .sheet(item: $editing) { d in AddEditDebtView(debt: d) }
            .sheet(item: $payingDebt) { d in
                DebtPaymentSheet(debt: d, wallets: wallets)
            }
            .alert("Error", isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })) {
                Button("OK") { errorMsg = nil }
            } message: { Text(errorMsg ?? "") }
        }
    }

    private func delete(_ debt: LocalDebt) async {
        do { try await DebtService.shared.delete(debt, in: modelContext) }
        catch { errorMsg = error.localizedDescription }
    }
}

private struct DebtRow: View {
    let debt: LocalDebt

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(debt.type == "lend" ? Color.blue.opacity(0.12) : Color.orange.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: debt.type == "lend" ? "arrow.up.right" : "arrow.down.left")
                    .foregroundColor(debt.type == "lend" ? .blue : .orange)
                    .font(.system(size: 18, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(debt.personName).fontWeight(.medium)
                HStack(spacing: 4) {
                    Text(debt.type == "lend" ? "Lent" : "Borrowed")
                    if let due = debt.dueDate {
                        Text("·")
                        Text("Due \(due.formatted(.dateTime.month(.abbreviated).day()))")
                    }
                }
                .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(debt.remainingAmount.formatted(currency: "VND"))
                    .fontWeight(.semibold)
                    .foregroundColor(debt.status == "completed" ? .secondary : .primary)
                statusBadge
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusBadge: some View {
        let (label, color): (String, Color) = switch debt.status {
        case "completed": ("Done", .green)
        case "overdue": ("Overdue", .red)
        default: ("Active", .blue)
        }
        Text(label)
            .font(.caption2).fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12))
            .cornerRadius(4)
    }
}

// MARK: - Debt Payment Sheet

struct DebtPaymentSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let debt: LocalDebt
    let wallets: [LocalWallet]

    @State private var amount: Double = 0
    @State private var note = ""
    @State private var selectedWalletId: UUID?
    @State private var isSaving = false
    @State private var errorMsg: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0", value: $amount, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).fontWeight(.semibold)
                        Text("₫").foregroundColor(.secondary)
                    }
                    TextField("Note (optional)", text: $note)
                }
                Section("Wallet") {
                    Picker("Wallet", selection: $selectedWalletId) {
                        Text("None").tag(UUID?.none)
                        ForEach(wallets, id: \.serverId) { w in
                            Text(w.name).tag(Optional(w.serverId))
                        }
                    }
                }
            }
            .navigationTitle("Record Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView().scaleEffect(0.8) }
                    else {
                        Button("Save") { Task { await pay() } }
                            .disabled(amount <= 0)
                    }
                }
            }
            .alert("Error", isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })) {
                Button("OK") { errorMsg = nil }
            } message: { Text(errorMsg ?? "") }
        }
        .onAppear { amount = debt.remainingAmount }
    }

    private func pay() async {
        isSaving = true; defer { isSaving = false }
        let wallet = wallets.first { $0.serverId == selectedWalletId }
        do {
            try await DebtService.shared.recordPayment(debt, amount: amount, note: note.isEmpty ? nil : note, wallet: wallet, in: modelContext)
            dismiss()
        } catch { errorMsg = error.localizedDescription }
    }
}
