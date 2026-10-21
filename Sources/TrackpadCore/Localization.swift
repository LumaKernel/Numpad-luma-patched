import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case korean = "ko"

    public var name: String { self == .english ? "English" : "한국어" }

    /// An explicit English default, independent of the system's language order.
    public static func load(from defaults: UserDefaults = .standard) -> AppLanguage {
        defaults.string(forKey: "appLanguage").flatMap(AppLanguage.init(rawValue:)) ?? .english
    }
}

public enum AppLocalization {
    public static func text(_ key: String, language: AppLanguage = .english) -> String {
        guard let url = Bundle.module.url(forResource: language.rawValue, withExtension: "lproj"),
              let bundle = Bundle(url: url) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }
}

/// Store the source message, so existing status text changes language immediately.
public struct LocalizedMessage {
    public let key: String
    public let count: Int?

    public init(_ key: String, count: Int? = nil) {
        self.key = key
        self.count = count
    }

    public func text(language: AppLanguage) -> String {
        let template = AppLocalization.text(key, language: language)
        guard let count else { return template }
        return String(format: template, locale: Locale(identifier: language.rawValue), count)
    }
}
