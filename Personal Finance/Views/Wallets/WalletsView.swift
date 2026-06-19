import SwiftUI
import SwiftData

struct WalletsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LocalWallet.name) private var wallets: [LocalWallet]
    @StateObject private var sync = SyncManager.shared

    @State private var showAdd = false
    @State private var editing: LocalWallet?
    @State private var errorMsg: String?

    private var totalBalance: Double { wallets.reduce(0) { $0 + $1.balance } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total Balance")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(totalBalance.formatted(currency: "VND"))
                                .font(.system(.title2, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundColor(totalBalance >= 0 ? .primary : .red)
                        }
                        Spacer()
                        Image(systemName: "creditcard.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .padding(.vertical, 4)
                }

                Section(wallets.isEmpty ? "" : "\(wallets.count) wallets") {
                    if wallets.isEmpty {
                        ContentUnavailableView(
                            "No Wallets",
                            systemImage: "creditcard",
                            description: Text("Tap + to add your first wallet")
                        )
                        .padding(.vertical)
                    } else {
                        ForEach(wallets, id: \.serverId) { wallet in
                            WalletRow(wallet: wallet)
                                .contentShape(Rectangle())
                                .onTapGesture { editing = wallet }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        Task { await deleteWallet(wallet) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Wallets")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .refreshable { await sync.syncAll(modelContext: modelContext) }
            .sheet(isPresented: $showAdd) {
                AddEditWalletView(wallet: nil)
            }
            .sheet(item: $editing) { w in
                AddEditWalletView(wallet: w)
            }
            .errorAlert($errorMsg)
        }
    }

    private func deleteWallet(_ wallet: LocalWallet) async {
        do {
            try await WalletService.shared.delete(wallet, in: modelContext)
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}

// MARK: - Wallet Row

struct WalletRow: View {
    let wallet: LocalWallet

    var accentColor: Color {
        wallet.color.map { Color(hex: $0) } ?? .blue
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Text(wallet.displayIcon).font(.system(size: 22))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(wallet.name)
                        .font(.subheadline).fontWeight(.medium)
                    if wallet.isDefault {
                        StatusBadge(label: "Default", color: .blue)
                    }
                }
                Text(wallet.typeLabel)
                    .font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            Text(wallet.balance.formatted(currency: "VND"))
                .font(.subheadline).fontWeight(.semibold)
                .foregroundColor(wallet.balance < 0 ? .red : .primary)
        }
        .padding(.vertical, 4)
    }
}
