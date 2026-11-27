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
    static func label(_ key: String, in language: AppLanguage) -> String {
        switch key {
        case "food_drink": language.text("Food and drink")
        case "transport": language.text("Transport and vehicles")
        case "home": language.text("Home and utilities")
        case "shopping": language.text("Shopping and personal care")
        case "health": language.text("Health")
        case "education": language.text("Education and work")
        case "entertainment": language.text("Entertainment and subscriptions")
        case "travel": language.text("Travel")
        case "family_pets": language.text("Family and pets")
        case "giving": language.text("Gifts and giving")
        case "fees": language.text("Fees and obligations")
        case "income": language.text("Income")
        default: key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
