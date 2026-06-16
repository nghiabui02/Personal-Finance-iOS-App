import Foundation
import SwiftData

@MainActor
final class WalletService {
    static let shared = WalletService()
    private let client = SupabaseService.shared.client
    private init() {}

    func create(
        name: String, type: String, initialBalance: Double,
        icon: String?, color: String?, isDefault: Bool,
        in ctx: ModelContext
    ) async throws {
        let userId = try await client.auth.session.user.id
        struct Body: Encodable {
            let user_id: String, name: String, type: String
            let balance: Double, icon: String?, color: String?, is_default: Bool
        }
        let remote: RemoteWallet = try await client
            .from("wallets")
            .insert(Body(user_id: userId.uuidString, name: name, type: type,
                         balance: initialBalance, icon: icon, color: color, is_default: isDefault))
            .select().single().execute().value
        ctx.insert(LocalWallet(from: remote))
        try ctx.save()
    }

    func update(
        _ wallet: LocalWallet, name: String, type: String,
        icon: String?, color: String?, isDefault: Bool,
        in ctx: ModelContext
    ) async throws {
        struct Body: Encodable {
            let name: String, type: String, icon: String?, color: String?, is_default: Bool
        }
        let remote: RemoteWallet = try await client
            .from("wallets")
            .update(Body(name: name, type: type, icon: icon, color: color, is_default: isDefault))
            .eq("id", value: wallet.serverId)
            .select().single().execute().value
        wallet.update(from: remote)
        try ctx.save()
    }

    func delete(_ wallet: LocalWallet, in ctx: ModelContext) async throws {
        try await client.from("wallets").delete().eq("id", value: wallet.serverId).execute()
        ctx.delete(wallet)
        try ctx.save()
    }
}
