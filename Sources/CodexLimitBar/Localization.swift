import Foundation

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case ukrainian = "uk"
    case russian = "ru"

    private static let defaultsKey = "appLanguage"

    static var current: AppLanguage {
        if let stored = UserDefaults.standard.string(forKey: defaultsKey),
           let language = AppLanguage(rawValue: stored) {
            return language
        }

        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        if preferred.hasPrefix("uk") { return .ukrainian }
        if preferred.hasPrefix("ru") { return .russian }
        return .english
    }

    var nativeName: String {
        switch self {
        case .english: return "English"
        case .ukrainian: return "Українська"
        case .russian: return "Русский"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    static func select(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: defaultsKey)
        UserDefaults.standard.synchronize()
    }
}

enum L10n {
    static let language = AppLanguage.current

    private static let languageBundle: Bundle = {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }()

    static func string(_ key: String) -> String {
        languageBundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: language.locale, arguments: arguments)
    }
}
