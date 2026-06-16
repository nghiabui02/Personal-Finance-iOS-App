import SwiftUI
import SwiftData

struct AddEditDebtView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let debt: LocalDebt?

    @Query(sort: \LocalWallet.name) private var wallets: [LocalWallet]

    @State private var type = "lend"
    @State private var personName = ""
    @State private var personContact = ""
    @State private var amount: Double = 0
    @State private var amountText = ""
    @State private var selectedWalletId: UUID?
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorMsg: String?

    private var isEditing: Bool { debt != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !isEditing {
                        Picker("Type", selection: $type) {
                            Text("I Lend").tag("lend")
                            Text("I Borrow").tag("borrow")
                        }
                        .pickerStyle(.segmented)
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
                    } else {
                        HStack {
                            Text("Type")
                            Spacer()
                            Text(debt?.type == "lend" ? "I Lend" : "I Borrow").foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Original Amount")
                            Spacer()
                            Text((debt?.amount ?? 0).formatted(currency: "VND")).foregroundColor(.secondary)
                        }
                    }
                }

                Section("Person") {
                    HStack {
                        Text("Name")
                        TextField("Person name", text: $personName).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Contact")
                        TextField("Phone / email (optional)", text: $personContact).multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    if !isEditing {
                        Picker("Wallet", selection: $selectedWalletId) {
                            Text("None").tag(UUID?.none)
                            ForEach(wallets, id: \.serverId) { w in
                                Text(w.name).tag(Optional(w.serverId))
                            }
                        }
                    }
                    Toggle("Due Date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("", selection: $dueDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }
                }

                Section {
                    TextField("Note (optional)", text: $note, axis: .vertical).lineLimit(2...4)
                }
            }
            .navigationTitle(isEditing ? "Edit Debt" : "New Debt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView().scaleEffect(0.8) }
                    else {
                        Button("Save") { Task { await save() } }
                            .disabled(personName.trimmingCharacters(in: .whitespaces).isEmpty || (!isEditing && amount <= 0))
                    }
                }
            }
            .alert("Error", isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })) {
                Button("OK") { errorMsg = nil }
            } message: { Text(errorMsg ?? "") }
        }
        .onAppear {
            if let d = debt {
                type = d.type; personName = d.personName
                personContact = d.personContact ?? ""
                note = d.note ?? ""
                if let dd = d.dueDate { hasDueDate = true; dueDate = dd }
            }
        }
    }

    private func save() async {
        let name = personName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isSaving = true; defer { isSaving = false }
        do {
            if let d = debt {
                try await DebtService.shared.update(
                    d, personName: name,
                    personContact: personContact.isEmpty ? nil : personContact,
                    dueDate: hasDueDate ? dueDate : nil,
                    note: note.isEmpty ? nil : note, in: modelContext
                )
            } else {
                guard amount > 0 else { return }
                let wallet = wallets.first { $0.serverId == selectedWalletId }
                try await DebtService.shared.create(
                    type: type, personName: name,
                    personContact: personContact.isEmpty ? nil : personContact,
                    amount: amount, walletId: selectedWalletId,
                    dueDate: hasDueDate ? dueDate : nil,
                    note: note.isEmpty ? nil : note,
                    wallet: wallet, in: modelContext
                )
            }
            dismiss()
        } catch { errorMsg = error.localizedDescription }
    }
}
