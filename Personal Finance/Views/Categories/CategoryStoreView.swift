import SwiftData
import SwiftUI

struct CategoryStoreView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var templates: [CategoryCatalogTemplate] = []
    @State private var selected = Set<UUID>()
    @State private var type = "expense"
    @State private var collection: String?
    @State private var search = ""
    @State private var isSelecting = false
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var language: AppLanguage { AppLocalization.shared.language }

    private var collections: [String] {
        Set(templates.filter { $0.type == type }.map(\.collection))
            .sorted { CategoryCollection.label($0, in: language) < CategoryCollection.label($1, in: language) }
    }

    private var visible: [CategoryCatalogTemplate] {
        let words = CategoryCatalogTemplate.normalize(search).split(whereSeparator: \.isWhitespace).map(String.init)
        return templates.filter {
            $0.type == type && (collection == nil || $0.collection == collection) && $0.matches(words)
        }.sorted { $0.name(in: language).localizedStandardCompare($1.name(in: language)) == .orderedAscending }
    }

    private var membershipsByTemplate: [UUID: RemoteCategory] {
        Dictionary(
            CategoryDirectory.shared.memberships.values.compactMap { membership in
                membership.templateId.map { ($0, membership) }
            }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        NavigationStack {
            List {
                filters
                catalogRows
            }
            .overlay {
                if isLoading && templates.isEmpty { ProgressView() }
            }
            .navigationTitle("Category Store")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search categories")
            .toolbar { actions }
            .safeAreaInset(edge: .bottom) {
                if isSelecting {
                    Button {
                        Task { await adopt(templates.filter { selected.contains($0.id) }) }
                    } label: {
                        Text("Add \(selected.count) categories").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected.isEmpty || isSaving)
                    .padding()
                    .background(.regularMaterial)
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .errorAlert($errorMessage)
        }
    }

    private var filters: some View {
        Section {
            Picker("Type", selection: $type) {
                Text("Expense").tag("expense")
                Text("Income").tag("income")
            }
            .pickerStyle(.segmented)
            .onChange(of: type) { _, _ in collection = nil }

            Picker("Collection", selection: $collection) {
                Text("All collections").tag(nil as String?)
                ForEach(collections, id: \.self) { key in
                    Text(CategoryCollection.label(key, in: language)).tag(Optional(key))
                }
            }
        }
    }

    @ViewBuilder private var catalogRows: some View {
        let memberships = membershipsByTemplate
        let rows = visible
        if !isLoading && rows.isEmpty {
            ContentUnavailableView("No matching categories", systemImage: "magnifyingglass")
        }
        ForEach(rows) { template in
            let membership = memberships[template.id]
            CatalogRow(
                name: membership?.label(in: language) ?? template.name(in: language),
                icon: membership?.icon ?? template.icon,
                added: membership?.isActive == true,
                removed: membership?.isActive == false,
                selecting: isSelecting, selected: selected.contains(template.id)
            ) {
                if isSelecting {
                    if !selected.insert(template.id).inserted { selected.remove(template.id) }
                } else {
                    Task { await adopt([template]) }
                }
            }
            .disabled(isSaving)
        }
    }

    @ToolbarContentBuilder private var actions: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(isSaving) }
        ToolbarItem(placement: .primaryAction) {
            Button(isSelecting ? "Cancel selection" : "Select") {
                isSelecting.toggle()
                selected.removeAll()
            }
            .disabled(isSaving || isLoading)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            templates = try await CategoryService.shared.catalog()
            await SyncManager.shared.syncAll(modelContext: modelContext)
            selected.subtract(membershipsByTemplate.values.filter(\.isActive).compactMap(\.templateId))
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.asDisplayableError().localizedDescription
        }
    }

    private func adopt(_ rows: [CategoryCatalogTemplate]) async {
        guard !rows.isEmpty, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await CategoryService.shared.adopt(rows, in: modelContext)
            selected.subtract(rows.map(\.id))
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.asDisplayableError().localizedDescription
        }
    }
}

private struct CatalogRow: View {
    let name: String
    let icon: String?
    let added: Bool
    let removed: Bool
    let selecting: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Text(icon ?? "📦").accessibilityHidden(true)
            Text(name)
            Spacer()
            if added {
                Label("Added", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if selecting {
                Button(action: action) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(selected ? "Deselect category" : "Select category"))
            } else {
                Button(removed ? "Add again" : "Add", action: action)
                    .buttonStyle(.bordered)
            }
        }
    }
}
