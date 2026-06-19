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
    @State private var colorHex = "3B82F6"
    @State private var isDefault = false
    @State private var isSaving = false
    @State private var errorMsg: String?

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
                        Label("Other", systemImage: "ellipsis.circle").tag("other")
                    }

                    if !isEditing {
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

                Section("Appearance") {
                    HStack {
                        Text("Icon")
                        Spacer()
                        EmojiPickerButton(emoji: $icon)
                    }

                    HStack {
                        Text("Color")
                        Spacer()
                        ColorSwatchPicker(selected: $colorHex)
                    }
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
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .errorAlert($errorMsg)
        }
        .onAppear { prefill() }
    }

    private func prefill() {
        guard let w = wallet else { return }
        name = w.name
        type = w.type
        icon = w.icon ?? ""
        colorHex = w.color ?? "3B82F6"
        isDefault = w.isDefault
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
                    in: modelContext
                )
            } else {
                try await WalletService.shared.create(
                    name: trimName, type: type, initialBalance: initialBalance,
                    icon: iconVal, color: colorHex, isDefault: isDefault,
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

    private let swatches: [(String, Color)] = [
        ("3B82F6", .blue),   ("10B981", .green),  ("8B5CF6", .purple),
        ("F59E0B", .orange), ("EF4444", .red),     ("14B8A6", .teal),
        ("6366F1", .indigo), ("EC4899", .pink),
    ]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(swatches, id: \.0) { hex, color in
                ZStack {
                    Circle().fill(color).frame(width: 26, height: 26)
                    if selected == hex {
                        Circle()
                            .stroke(Color.primary, lineWidth: 2)
                            .frame(width: 32, height: 32)
                    }
                }
                .onTapGesture { selected = hex }
            }
        }
    }
}
