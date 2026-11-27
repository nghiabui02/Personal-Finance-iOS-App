import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
    case vietnamese = "vi"
    case english = "en"

    var id: Self { self }
    var locale: Locale { Locale(identifier: rawValue) }
    var autonym: String { self == .vietnamese ? "Tiếng Việt" : "English" }

    static var deviceLanguage: Self {
        for identifier in Locale.preferredLanguages {
            if let code = Locale(identifier: identifier).language.languageCode?.identifier,
                let language = Self(rawValue: code) {
                return language
            }
        }
        return .vietnamese
    }

    func text(_ key: String, _ arguments: CVarArg...) -> String {
        let bundle = Self.bundles[self] ?? .main
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        return arguments.isEmpty ? format : String(format: format, locale: locale, arguments: arguments)
    }

    private static let bundles: [Self: Bundle] = .init(
        uniqueKeysWithValues: allCases.compactMap { language in
            guard let url = Bundle.main.url(forResource: language.rawValue, withExtension: "lproj"),
                let bundle = Bundle(url: url)
            else { return nil }
            return (language, bundle)
        })
}

@MainActor
@Observable
final class AppLocalization {
    static let shared = AppLocalization()
    var language = AppLanguage.deviceLanguage

    private init() {}
}
