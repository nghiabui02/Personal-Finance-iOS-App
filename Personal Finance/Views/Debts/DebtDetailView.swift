import SwiftData
import SwiftUI

struct DebtDetailView: View {
    @Query(sort: \LocalWallet.name) private var wallets: [LocalWallet]
    @StateObject private var history: DebtPaymentHistoryViewModel

    let debt: LocalDebt

    @State private var activeSheet: DebtDetailSheet?

    init(debt: LocalDebt) {
        self.debt = debt
        _history = StateObject(
            wrappedValue: DebtPaymentHistoryViewModel(debtId: debt.serverId)
        )
    }

    private var linkedWallet: LocalWallet? {
        wallets.first { $0.serverId == debt.walletId }
    }

    var body: some View {
        List {
            Section {
                DebtDetailHeader(debt: debt)
            }
            DebtDetailActionsSection(
                debt: debt,
                onRecordPayment: { activeSheet = .payment },
                onAddAmount: { activeSheet = .addition }
            )
            DebtInformationSection(
                debt: debt,
                linkedWallet: linkedWallet
            )
            DebtPaymentHistorySection(
                payments: history.payments,
                isLoading: history.isLoading,
                errorMessage: history.errorMessage
            )
        }
        .listStyle(.insetGrouped)
        .navigationTitle(debt.personName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    activeSheet = .edit
                }
            }
        }
        .sheet(item: $activeSheet, onDismiss: refreshHistory) { sheet in
            sheetContent(sheet)
        }
        .task {
            await history.load()
        }
        .refreshable {
            await history.load()
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: DebtDetailSheet) -> some View {
        switch sheet {
        case .edit:
            AddEditDebtView(debt: debt)
        case .payment:
            DebtPaymentSheet(debt: debt, wallets: wallets)
        case .addition:
            DebtAdditionSheet(debt: debt, wallets: wallets)
        }
    }

    private func refreshHistory() {
        guard activeSheet == nil else { return }
        Task {
            await history.load()
        }
    }
}

private enum DebtDetailSheet: String, Identifiable {
    case edit
    case payment
    case addition

    var id: String { rawValue }
}
