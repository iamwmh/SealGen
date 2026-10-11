import Foundation

extension Locale {
    /// Chinese UI for any Chinese language, including Traditional. Everything else uses English.
    var usesChinese: Bool {
        if let code = language.languageCode?.identifier, !code.isEmpty {
            return code.hasPrefix("zh")
        }
        let preferred = Locale.preferredLanguages.first ?? identifier
        return preferred.hasPrefix("zh")
    }

    func text(_ chinese: String, _ english: String) -> String {
        usesChinese ? chinese : english
    }
}

enum UIText {
    static func text(_ chinese: String, _ english: String) -> String {
        Locale.current.text(chinese, english)
    }
}
