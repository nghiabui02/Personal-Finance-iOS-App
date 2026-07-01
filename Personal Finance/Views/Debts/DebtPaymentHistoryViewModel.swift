import Combine
import Foundation

@MainActor
final class DebtPaymentHistoryViewModel: ObservableObject {
    @Published private(set) var payments: [RemoteDebtPayment] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let debtId: UUID
    private let client = SupabaseService.shared.client

    init(debtId: UUID) {
        self.debtId = debtId
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            payments = try await client
                .from("debt_payments")
                .select()
                .eq("debt_id", value: debtId)
                .order("paid_at", ascending: false)
                .execute()
                .value
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
