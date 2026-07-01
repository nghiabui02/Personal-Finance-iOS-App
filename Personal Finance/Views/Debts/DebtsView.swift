import SwiftUI
import SwiftData

struct DebtsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalDebt.personName) private var allDebts: [LocalDebt]
    @Query(sort: \LocalWallet.name) private var wallets: [LocalWallet]
    @StateObject private var sync = SyncManager.shared

    @State private var showAdd = false
    @State private var payingDebt: LocalDebt?
    @State private var addingDebt: LocalDebt?
    @State private var pendingDeletion: LocalDebt?
    @State private var showDeleteConfirmation = false
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
        VStack(spacing: 0) {
            Picker("Filter", selection: $filterType) {
                    ForEach(FilterType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .tint(filterType == .lend ? .lend : filterType == .borrow ? .borrow : .blue)
                .padding(.horizontal).padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))

                List {
                    if !active.isEmpty {
                        Section("Active") {
                            ForEach(active, id: \.serverId) { debt in
                                NavigationLink {
                                    DebtDetailView(debt: debt)
                                } label: {
                                    DebtRow(debt: debt)
                                }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            payingDebt = debt
                                        } label: { Label("Pay", systemImage: "checkmark.circle") }
                                        .tint(.green)
                                        Button {
                                            addingDebt = debt
                                        } label: { Label("Add", systemImage: "plus.circle") }
                                        .tint(.orange)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button {
                                            pendingDeletion = debt
                                            showDeleteConfirmation = true
                                        } label: { Label("Delete", systemImage: "trash") }
                                        .tint(.red)
                                    }
                            }
                        }
                    }
                    if !completed.isEmpty {
                        Section("Completed") {
                            ForEach(completed, id: \.serverId) { debt in
                                NavigationLink {
                                    DebtDetailView(debt: debt)
                                } label: {
                                    DebtRow(debt: debt)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await sync.syncAll(modelContext: modelContext) }
                .overlay {
                    if filtered.isEmpty {
                        ContentUnavailableView("No Debts", systemImage: "dollarsign.circle",
                            description: Text("Tap + to add a debt record"))
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Debts")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) { AddEditDebtView(debt: nil) }
            .sheet(item: $payingDebt) { d in
                DebtPaymentSheet(debt: d, wallets: wallets)
            }
            .sheet(item: $addingDebt) { d in
                DebtAdditionSheet(debt: d, wallets: wallets)
            }
            .deleteConfirmation(
                item: $pendingDeletion,
                isPresented: $showDeleteConfirmation,
                title: "Delete Debt?",
                message: "The debt and its payment history will be permanently deleted. Existing wallet transactions will not be reversed."
            ) { debt in
                Task { await delete(debt) }
            }
            .errorAlert($errorMsg)
    }

    private func delete(_ debt: LocalDebt) async {
        do { try await DebtService.shared.delete(debt, in: modelContext) }
        catch { errorMsg = error.localizedDescription }
    }
}

private struct DebtRow: View {
    let debt: LocalDebt

    private var paidAmount: Double { debt.amount - debt.remainingAmount }
    private var progress: Double { debt.amount > 0 ? max(0, min(1, paidAmount / debt.amount)) : 0 }
    private var accentColor: Color { debt.type == "lend" ? .lend : .borrow }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: debt.type == "lend" ? "arrow.up.right" : "arrow.down.left")
                        .foregroundColor(accentColor)
                        .font(.system(size: 18, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(debt.personName).fontWeight(.medium)
                    HStack(spacing: 4) {
                        Text(debt.type == "lend" ? "Lent" : "Borrowed")
                        if let due = debt.dueDate {
                            Text("·")
                            Text("Due \(due.formatted(.dateTime.month(.abbreviated).day()))")
                                .foregroundColor(debt.status == "overdue" ? .red : .secondary)
                        }
                    }
                    .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                statusBadge
            }

            VStack(spacing: 4) {
                HStack {
                    Text("Paid \(paidAmount.formatted(currency: "VND"))")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text("\(debt.remainingAmount.formatted(currency: "VND")) left")
                        .font(.caption).fontWeight(.medium)
                        .foregroundColor(debt.status == "completed" ? .secondary : .primary)
                }
                ProgressView(value: progress)
                    .tint(accentColor)
                HStack {
                    Spacer()
                    Text("of \(debt.amount.formatted(currency: "VND"))")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        let (label, color): (String, Color) = switch debt.status {
        case "completed": ("Done", .green)
        case "overdue": ("Overdue", .red)
        default: ("Active", .blue)
        }
        StatusBadge(label: label, color: color)
    }
}

// MARK: - Debt Payment Sheet

struct DebtPaymentSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let debt: LocalDebt
    let wallets: [LocalWallet]

    @State private var amount: Double = 0
    @State private var amountText = ""
    @State private var note = ""
    @State private var date = Date()
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
                        TextField("0", text: $amountText)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).fontWeight(.semibold)
                            .onChange(of: amountText) { _, new in
                                applyAmountFormat(new: new, amountText: &amountText, amount: &amount)
                            }
                        Text("₫").foregroundColor(.secondary)
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
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
            .formKeyboardHandling()
            .navigationTitle("Record Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView().scaleEffect(0.8) }
                    else {
                        Button("Save") { Task { await pay() } }
                            .disabled(amount <= 0 || amount > debt.remainingAmount)
                    }
                }
            }
            .errorAlert($errorMsg)
        }
    }

    private func pay() async {
        isSaving = true; defer { isSaving = false }
        let wallet = wallets.first { $0.serverId == selectedWalletId }
        do {
            try await DebtService.shared.recordPayment(
                debt, amount: amount,
                note: note.isEmpty ? nil : note,
                date: date, wallet: wallet, in: modelContext
            )
            dismiss()
        } catch { errorMsg = error.localizedDescription }
    }
}

// MARK: - Debt Addition Sheet

struct DebtAdditionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let debt: LocalDebt
    let wallets: [LocalWallet]

    @State private var amount: Double = 0
    @State private var amountText = ""
    @State private var note = ""
    @State private var date = Date()
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
                        TextField("0", text: $amountText)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).fontWeight(.semibold)
                            .onChange(of: amountText) { _, new in
                                applyAmountFormat(new: new, amountText: &amountText, amount: &amount)
                            }
                        Text("₫").foregroundColor(.secondary)
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
                }
                Section("Wallet (optional)") {
                    Picker("Wallet", selection: $selectedWalletId) {
                        Text("None").tag(UUID?.none)
                        ForEach(wallets, id: \.serverId) { w in
                            Text(w.name).tag(Optional(w.serverId))
                        }
                    }
                }
            }
            .formKeyboardHandling()
            .navigationTitle("Add to \(debt.type == "lend" ? "Lending" : "Borrowing")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView().scaleEffect(0.8) }
                    else {
                        Button("Save") { Task { await add() } }
                            .disabled(amount <= 0)
                    }
                }
            }
            .errorAlert($errorMsg)
        }
    }

    private func add() async {
        isSaving = true; defer { isSaving = false }
        let wallet = wallets.first { $0.serverId == selectedWalletId }
        do {
            try await DebtService.shared.addAmount(
                to: debt, amount: amount,
                note: note.isEmpty ? nil : note,
                date: date, wallet: wallet, in: modelContext
            )
            dismiss()
        } catch { errorMsg = error.localizedDescription }
    }
}
