import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case korean = "ko"
    case japanese = "ja"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .english, .korean, .japanese:
            return Locale(identifier: rawValue)
        }
    }
}

enum L10n {
    static let languageDefaultsKey = "appLanguage"

    static func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: arguments)
    }

    private static var bundle: Bundle {
        guard
            let rawValue = UserDefaults.standard.string(forKey: languageDefaultsKey),
            let language = AppLanguage(rawValue: rawValue),
            language != .system,
            let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return .main
        }

        return bundle
    }
}
