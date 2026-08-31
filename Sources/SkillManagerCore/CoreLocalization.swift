import Foundation

enum CoreL10n {
    static var isSimplifiedChinese: Bool {
        let preferred = Bundle.main.preferredLocalizations.first
            ?? Locale.preferredLanguages.first
            ?? "en"
        return preferred.lowercased().hasPrefix("zh")
    }

    static func choose(_ simplifiedChinese: String, _ english: String) -> String {
        isSimplifiedChinese ? simplifiedChinese : english
    }
}
