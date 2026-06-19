import Foundation
import SwiftData

@MainActor
final class TransferService {
    static let shared = TransferService()
    private let client = SupabaseService.shared.client
    private init() {}

    private let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    func transfer(
        from fromWallet: LocalWallet,
        to toWallet: LocalWallet,
        amount: Double,
        date: Date,
        note: String?,
        in ctx: ModelContext
    ) async throws {
        let session = try await client.auth.session
        let token = session.accessToken

        guard let url = URL(string: "\(AppConfig.webAppURL)/api/transfers") else {
            throw TransferError.invalidConfiguration
        }

        struct RequestBody: Encodable {
            let from_wallet_id: String
            let to_wallet_id: String
            let amount: Double
            let note: String?
            let transfer_date: String
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RequestBody(
            from_wallet_id: fromWallet.serverId.uuidString.lowercased(),
            to_wallet_id: toWallet.serverId.uuidString.lowercased(),
            amount: amount,
            note: note?.isEmpty == true ? nil : note,
            transfer_date: df.string(from: date)
        ))

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw TransferError.invalidResponse
        }

        guard http.statusCode == 201 else {
            let message = parseErrorMessage(from: data) ?? "Status \(http.statusCode)"
            throw TransferError.serverError(http.statusCode, message)
        }

        // Update local balances immediately for instant UI feedback
        fromWallet.balance -= amount
        toWallet.balance += amount
        try ctx.save()
    }

    private func parseErrorMessage(from data: Data) -> String? {
        struct ErrorBody: Decodable {
            let error: String?
            let message: String?
        }
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data) {
            return body.error ?? body.message
        }
        return String(data: data, encoding: .utf8).flatMap { $0.isEmpty ? nil : $0 }
    }
}

enum TransferError: LocalizedError {
    case invalidConfiguration
    case invalidResponse
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "Web app URL not configured"
        case .invalidResponse: return "Invalid server response"
        case .serverError(let code, let msg):
            switch code {
            case 400: return "Transfer failed: \(msg)"
            case 401: return "Not authenticated. Please sign in again."
            case 404: return "Wallet not found"
            default:  return "Server error (\(code)): \(msg)"
            }
        }
    }
}
