import Foundation
import Supabase

enum FinanceValidationError: LocalizedError {
    case invalidAmount
    case sameWallet
    case insufficientFunds
    case exceedsRemainingDebt
    case exceedsCreditDebt
    case missingDefaultWallet

    var errorDescription: String? {
        switch self {
        case .invalidAmount: return "Amount must be greater than zero."
        case .sameWallet: return "Source and destination wallets must be different."
        case .insufficientFunds: return "The source wallet has insufficient funds."
        case .exceedsRemainingDebt: return "Payment cannot exceed the remaining debt."
        case .exceedsCreditDebt: return "Payment cannot exceed the outstanding credit balance."
        case .missingDefaultWallet: return "Choose another default wallet before deleting a wallet with a positive balance."
        }
    }
}

final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: URL(string: AppConfig.supabaseURL)!,
            supabaseKey: AppConfig.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }
}
