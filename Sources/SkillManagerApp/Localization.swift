import Foundation
import SwiftUI

enum L10n {
    static var languageIdentifier: String {
        let preferred = Bundle.main.preferredLocalizations.first
            ?? Locale.preferredLanguages.first
            ?? "en"
        return preferred.lowercased().hasPrefix("zh") ? "zh-Hans" : "en"
    }

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        let format = localizedFormat(for: key)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale.current, arguments: arguments)
    }

    private static func localizedFormat(for key: String) -> String {
        let bundles = [Bundle.main, Bundle.module]
        for bundle in bundles {
            if let path = bundle.path(forResource: languageIdentifier, ofType: "lproj"),
               let localizedBundle = Bundle(path: path) {
                let value = localizedBundle.localizedString(forKey: key, value: nil, table: nil)
                if value != key || languageIdentifier == "zh-Hans" {
                    return value
                }
            }
        }
        return key
    }
}

extension AppModel {
    func localized(_ key: String, _ arguments: CVarArg...) -> String {
        let format = L10n.string(key)
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}
