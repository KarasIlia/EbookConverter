import Foundation

/// An entry of the inspector's language picker.
struct LanguageOption: Identifiable, Hashable {
    /// Language tag stored in the book metadata ("und" when undetermined).
    let code: String
    /// Localized language name; `nil` for "und", which is shown as "Undetermined".
    let name: String?

    var id: String { code }

    static let undetermined = "und"

    /// Locale of the app's UI, so language names match the interface language rather than the region.
    private static let uiLocale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")

    /// `code`, with an empty tag treated as undetermined so a picker selection always has an entry.
    static func normalized(_ code: String) -> String {
        code.isEmpty ? undetermined : code
    }

    /// All ISO languages with a localized name, sorted by that name.
    private static let allLanguages: [LanguageOption] = Locale.LanguageCode.isoLanguageCodes
        .compactMap { code in
            guard code.identifier != undetermined,
                  let name = uiLocale.localizedString(forLanguageCode: code.identifier)
            else { return nil }
            return LanguageOption(code: code.identifier, name: capitalized(name))
        }
        .sorted { $0.name?.localizedStandardCompare($1.name ?? "") == .orderedAscending }

    /// Some locales write language names in lowercase ("английский"); a menu item starts with a capital.
    private static func capitalized(_ name: String) -> String {
        name.prefix(1).uppercased(with: uiLocale) + name.dropFirst()
    }

    /// Picker entries: the book's own language first (even a tag such as "zh-Hans" outside the ISO
    /// list, or "und"), then every other language by name.
    static func options(bookLanguage: String) -> [LanguageOption] {
        let first = if normalized(bookLanguage) == undetermined {
            LanguageOption(code: undetermined, name: nil)
        } else {
            LanguageOption(
                code: bookLanguage,
                name: uiLocale.localizedString(forIdentifier: bookLanguage).map(capitalized) ?? bookLanguage
            )
        }
        return [first] + allLanguages.filter { $0.code != first.code }
    }
}
