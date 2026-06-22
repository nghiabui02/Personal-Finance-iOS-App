import SwiftUI
import SwiftData

struct AddEditWalletView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let wallet: LocalWallet?

    @State private var name = ""
    @State private var type = "cash"
    @State private var initialBalance: Double = 0
    @State private var initialBalanceText = ""
    @State private var icon = ""
    @State private var colorHex = "EAB308"
    @State private var isDefault = false
    @State private var isSaving = false
    @State private var errorMsg: String?

    // Credit wallet fields
    @State private var creditLimit: Double = 0
    @State private var creditLimitText = ""
    @State private var statementDay: Int = 15
    @State private var paymentDueDay: Int = 5

    private var isEditing: Bool { wallet != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Wallet name", text: $name)

                    Picker("Type", selection: $type) {
                        Label("Cash", systemImage: "banknote").tag("cash")
                        Label("Bank", systemImage: "building.columns").tag("bank")
                        Label("E-Wallet", systemImage: "iphone").tag("e_wallet")
                        Label("Investment", systemImage: "chart.line.uptrend.xyaxis").tag("investment")
                        Label("Credit", systemImage: "creditcard").tag("credit")
                        Label("Other", systemImage: "ellipsis.circle").tag("other")
                    }

                    if !isEditing && type != "credit" {
                        HStack {
                            Text("Initial Balance")
                            Spacer()
                            TextField("0", text: $initialBalanceText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: initialBalanceText) { _, new in
                                    applyAmountFormat(new: new, amountText: &initialBalanceText, amount: &initialBalance)
                                }
                        }
                    }
                }

                if type == "credit" {
                    Section("Credit") {
                        HStack {
                            Text("Credit Limit")
                            Spacer()
                            TextField("0", text: $creditLimitText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: creditLimitText) { _, new in
                                    applyAmountFormat(new: new, amountText: &creditLimitText, amount: &creditLimit)
                                }
                            Text("₫").foregroundColor(.secondary)
                        }
                        Stepper("Statement Day: \(statementDay)", value: $statementDay, in: 1...28)
                        Stepper("Payment Due Day: \(paymentDueDay)", value: $paymentDueDay, in: 1...28)
                    }
                }

                Section("Appearance") {
                    HStack {
                        Text("Icon")
                        Spacer()
                        EmojiPickerButton(emoji: $icon)
                    }
                    ColorSwatchPicker(selected: $colorHex)
                }

                Section {
                    Toggle("Set as default wallet", isOn: $isDefault)
                }
            }
            .formKeyboardHandling()
            .navigationTitle(isEditing ? "Edit Wallet" : "New Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(isSaveDisabled)
                    }
                }
            }
            .errorAlert($errorMsg)
        }
        .onAppear { prefill() }
    }

    private var isSaveDisabled: Bool {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        if type == "credit" && !isEditing && creditLimit <= 0 { return true }
        return false
    }

    private func prefill() {
        guard let w = wallet else { return }
        name = w.name
        type = w.type
        icon = w.icon ?? ""
        colorHex = (w.color ?? "EAB308")
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .uppercased()
        isDefault = w.isDefault
        if w.type == "credit" {
            creditLimit = w.creditLimit ?? 0
            if creditLimit > 0 { creditLimitText = creditLimit.formattedDecimal() }
            statementDay = w.statementDay ?? 15
            paymentDueDay = w.paymentDueDay ?? 5
        }
    }

    private func save() async {
        let trimName = name.trimmingCharacters(in: .whitespaces)
        guard !trimName.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        let iconVal: String? = icon.trimmingCharacters(in: .whitespaces).isEmpty ? nil : icon
        do {
            if let w = wallet {
                try await WalletService.shared.update(
                    w, name: trimName, type: type,
                    icon: iconVal, color: colorHex, isDefault: isDefault,
                    creditLimit: type == "credit" ? creditLimit : nil,
                    statementDay: type == "credit" ? statementDay : nil,
                    paymentDueDay: type == "credit" ? paymentDueDay : nil,
                    in: modelContext
                )
            } else {
                try await WalletService.shared.create(
                    name: trimName, type: type, initialBalance: initialBalance,
                    icon: iconVal, color: colorHex, isDefault: isDefault,
                    creditLimit: type == "credit" ? creditLimit : nil,
                    statementDay: type == "credit" ? statementDay : nil,
                    paymentDueDay: type == "credit" ? paymentDueDay : nil,
                    in: modelContext
                )
            }
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}

// MARK: - Color Swatch Picker

struct ColorSwatchPicker: View {
    @Binding var selected: String

    static let swatches: [String] = [
        "EF4444", "F97316", "EAB308", "22C55E", "06B6D4",
        "3B82F6", "8B5CF6", "EC4899", "64748B", "14B8A6",
    ]

    private let columns = Array(repeating: GridItem(.flexible()), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Self.swatches, id: \.self) { hex in
                let isSelected = selected.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                    .uppercased() == hex
                ZStack {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 30, height: 30)
                    if isSelected {
                        Circle()
                            .stroke(Color.primary, lineWidth: 2.5)
                            .frame(width: 37, height: 37)
                    }
                }
                .onTapGesture { selected = hex }
            }
        }
        .padding(.vertical, 4)
    }
}
