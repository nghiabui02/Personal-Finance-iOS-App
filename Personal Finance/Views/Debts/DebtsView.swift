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
    @State private var filterType: DebtFilterType = .all
    @State private var errorMsg: String?

    private var filteredDebts: [LocalDebt] {
        DebtFilter.apply(filterType, to: allDebts)
    }

    private var activeDebts: [LocalDebt] {
        filteredDebts.filter { $0.status == "active" || $0.status == "overdue" }
    }

    private var completedDebts: [LocalDebt] {
        filteredDebts.filter { $0.status == "completed" }
    }

    var body: some View {
        DebtsContentView(
            filterType: $filterType,
            activeDebts: activeDebts,
            completedDebts: completedDebts,
            isEmpty: filteredDebts.isEmpty,
            onPay: { payingDebt = $0 },
            onAdd: { addingDebt = $0 },
            onDelete: requestDelete,
            onRefresh: { await sync.syncAll(modelContext: modelContext) }
        )
        .navigationTitle("Debts")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddEditDebtView(debt: nil)
        }
        .sheet(item: $payingDebt) { debt in
            DebtPaymentSheet(debt: debt, wallets: wallets)
        }
        .sheet(item: $addingDebt) { debt in
            DebtAdditionSheet(debt: debt, wallets: wallets)
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

    private func requestDelete(_ debt: LocalDebt) {
        pendingDeletion = debt
        showDeleteConfirmation = true
    }

    private func delete(_ debt: LocalDebt) async {
        do {
            try await DebtService.shared.delete(debt, in: modelContext)
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}
