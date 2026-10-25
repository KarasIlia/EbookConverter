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
