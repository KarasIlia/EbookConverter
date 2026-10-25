/// Joins a wrapped line onto the text before it, the same way for every importer.
///
/// - A soft hyphen at the end is dropped.
/// - A hyphen ending a word is dropped before a lowercase continuation (`con-` + `tinued`),
///   kept before anything else (`Jean-` + `Paul`); no space is added either way.
/// - No space is added when both sides are in scripts written without spaces (CJK, Thai, Lao, Khmer, Myanmar).
/// - Otherwise a single space separates the lines.
enum LineJoiner {
    private static let softHyphen: Character = "\u{AD}"

    /// Prepares `text` to be followed by a line starting with `nextFirst`: trims its trailing whitespace,
    /// then repairs hyphenation or appends the separator.
    static func prepare(_ text: inout String, before nextFirst: Character?) {
        while text.last?.isWhitespace == true { text.removeLast() }
        guard let end = text.last else { return }
        if end == softHyphen {
            text.removeLast()
        } else if end == "-", text.dropLast().last.map({ !$0.isWhitespace }) ?? false {
            if let nextFirst, ScriptTraits.isLowercaseLetter(nextFirst) { text.removeLast() }
        } else if nextFirst != nil {
            text += separator(between: end, and: nextFirst)
        } else {
            text += " "
        }
    }

    /// The word separator between two characters: none when both are in scripts written without spaces, else a space.
    static func separator(between previous: Character?, and next: Character?) -> String {
        guard let previous, let next else { return " " }
        return ScriptTraits.isWrittenWithoutSpaces(previous) && ScriptTraits.isWrittenWithoutSpaces(next) ? "" : " "
    }

    /// `text` followed by `next` (leading whitespace of `next` dropped).
    static func joined(_ text: String, _ next: String) -> String {
        let next = next.drop { $0.isWhitespace }
        var result = text
        prepare(&result, before: next.first)
        return result + next
    }
}
