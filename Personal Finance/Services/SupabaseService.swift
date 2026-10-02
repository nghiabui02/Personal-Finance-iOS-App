import Foundation
import Supabase

/// Checks the app can make before a request is worth sending.
///
/// Every rule about money — sufficient funds, overpaying a debt, transferring to
/// the same wallet — is enforced by the database inside the transaction that
/// applies it, and comes back as a `BusinessRuleError` with the wallet name and
/// real figures filled in. Only checks that need no server state belong here.
enum FinanceValidationError: LocalizedError {
    case invalidWalletName

    var errorDescription: String? {
        switch self {
        case .invalidWalletName: return "Wallet name cannot be empty."
        }
    }
}

/// A rule the database enforced, phrased for the person who hit it.
///
/// The money functions raise these with SQLSTATE `P0001` and already word the
/// message for display ("Tiền mặt only has 2.450.000đ."), so it is shown as-is
/// rather than being mapped to a generic client-side string that would lose the
/// wallet name and the actual figure.
struct BusinessRuleError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension Error {
    /// Converts a database rule violation into a displayable error, leaving every
    /// other failure untouched.
    func asDisplayableError() -> Error {
        guard let postgrest = self as? PostgrestError, postgrest.code == "P0001" else { return self }
        return BusinessRuleError(message: postgrest.message)
    }
}

final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        guard let supabaseURL = URL(string: AppConfig.supabaseURL), supabaseURL.host != nil else {
            fatalError("Supabase URL is missing or invalid. Check Config/Secrets.xcconfig.")
        }
        client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: AppConfig.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }
}
