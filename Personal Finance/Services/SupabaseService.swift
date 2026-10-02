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
    /// Turns a failure into something worth showing.
    ///
    /// Two cases get rewritten: a rule the database enforced, which already reads
    /// as a sentence, and losing the connection — every write goes to the server,
    /// so "offline" is the useful explanation rather than the URLError text.
    func asDisplayableError() -> Error {
        if let postgrest = self as? PostgrestError, postgrest.code == "P0001" {
            return BusinessRuleError(message: postgrest.message)
        }
        if isOfflineError {
            return BusinessRuleError(
                message: "No internet connection. This app needs to be online to record changes."
            )
        }
        return self
    }

    private var isOfflineError: Bool {
        guard let urlError = self as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost,
             .cannotFindHost, .cannotConnectToHost, .timedOut,
             .dataNotAllowed, .internationalRoamingOff:
            return true
        default:
            return false
        }
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
