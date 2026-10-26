import Foundation

public struct BookMetadata: Sendable, Hashable {
    public var title: String
    /// BCP-47 language tag, e.g. "ru", "zh-Hans"; "und" if unknown.
    public var language: String
    public var author: String

    public init(title: String, author: String, language: String) {
        self.title = title
        self.author = author
        self.language = language
    }
}

extension BookMetadata {
    public var isRightToLeft: Bool {
        Locale.Language(identifier: language).characterDirection == .rightToLeft
    }
}

extension BookMetadata {
    /// Title written when a book has none.
    static let fallbackTitle = "Book"
    /// Language tag written when a book has none.
    static let undeterminedLanguage = "und"

    /// The metadata as writers emit it: fields trimmed, a blank title replaced by `fallbackTitle`
    /// and a blank language by `und`, since EPUB and FB2 require both.
    var normalizedForOutput: BookMetadata {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return BookMetadata(
            title: title.isEmpty ? Self.fallbackTitle : title,
            author: author.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language.isEmpty ? Self.undeterminedLanguage : language
        )
    }
}
