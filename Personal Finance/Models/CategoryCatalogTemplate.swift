import Foundation

struct CategoryCatalogTemplate: Decodable, Identifiable {
    static let columns = "id,default_key,name_en,name_vi,collection,search_aliases,type,icon,color"

    let id: UUID
    let key: String
    let nameEN: String
    let nameVI: String
    let collection: String
    let aliases: [String]
    let type: TransactionKind
    let icon: String?
    let color: String?

    enum CodingKeys: String, CodingKey {
        case id, collection, type, icon, color
        case key = "default_key"
        case nameEN = "name_en"
        case nameVI = "name_vi"
        case aliases = "search_aliases"
    }

    var labels: CategoryTemplate { CategoryTemplate(defaultKey: key, nameEN: nameEN, nameVI: nameVI) }

    func name(in language: AppLanguage) -> String {
        language == .vietnamese ? nameVI : nameEN
    }

    func matches(_ words: [String]) -> Bool {
        guard !words.isEmpty else { return true }
        let haystack = ([nameEN, nameVI] + aliases).map(Self.normalize).joined(separator: " ")
        return words.allSatisfy { haystack.contains($0) }
    }

    static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi"))
            .replacingOccurrences(of: "đ", with: "d")
    }
}

enum CategoryCollection {
    /// English source text per catalog key; `AppLanguage.text` translates it.
    private static let labels: [String: String] = [
        "food_drink": "Food and drink",
        "transport": "Transport and vehicles",
        "home": "Home and utilities",
        "shopping": "Shopping and personal care",
        "health": "Health",
        "education": "Education and work",
        "entertainment": "Entertainment and subscriptions",
        "travel": "Travel",
        "family_pets": "Family and pets",
        "giving": "Gifts and giving",
        "fees": "Fees and obligations",
        "income": "Income"
    ]

    static func label(_ key: String, in language: AppLanguage) -> String {
        guard let label = labels[key] else { return key.replacingOccurrences(of: "_", with: " ").capitalized }
        return language.text(label)
    }
}
