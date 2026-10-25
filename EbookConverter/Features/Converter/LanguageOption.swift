import Foundation

/// An entry of the inspector's language picker.
struct LanguageOption: Identifiable, Hashable {
    /// Language tag stored in the book metadata ("und" when undetermined).
    let code: String
    /// Localized language name; `nil` for "und", which is shown as "Undetermined".
    let name: String?

    var id: String { code }

    static let undetermined = "und"

    /// All ISO languages with a localized name, sorted by that name.
    private static let allLanguages: [LanguageOption] = Locale.LanguageCode.isoLanguageCodes
        .compactMap { code in
            guard code.identifier != undetermined,
                  let name = Locale.current.localizedString(forLanguageCode: code.identifier)
            else { return nil }
            return LanguageOption(code: code.identifier, name: capitalized(name))
        }
        .sorted { $0.name?.localizedStandardCompare($1.name ?? "") == .orderedAscending }

    /// Some locales write language names in lowercase ("английский"); a menu item starts with a capital.
    private static func capitalized(_ name: String) -> String {
        name.prefix(1).uppercased(with: .current) + name.dropFirst()
    }

    /// Picker entries: the book's own language first (even a tag such as "zh-Hans" outside the ISO
    /// list, or "und"), then every other language by name.
    static func options(bookLanguage: String) -> [LanguageOption] {
        let first = if bookLanguage.isEmpty || bookLanguage == undetermined {
            LanguageOption(code: undetermined, name: nil)
        } else {
            LanguageOption(
                code: bookLanguage,
                name: Locale.current.localizedString(forIdentifier: bookLanguage).map(capitalized) ?? bookLanguage
            )
        }
        return [first] + allLanguages.filter { $0.code != first.code }
    }
}
