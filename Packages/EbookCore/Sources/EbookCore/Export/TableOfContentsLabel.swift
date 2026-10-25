/// How a chapter is named in the exported table of contents and headed in its text.
/// Shared by the writers and the app's sidebar and preview, so what the user sees is what the book shows.
public enum TableOfContentsLabel {
    /// Label of an untitled chapter that is not the first one.
    public static let untitledMark = "\u{2026}"

    /// The heading written at the top of the chapter, or `nil` when it has no (non-blank) title.
    public static func heading(of chapter: Chapter) -> String? {
        guard let title = chapter.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return title
    }

    /// The table-of-contents label: the chapter's title; for an untitled first chapter (the book's opening
    /// matter) the book title; otherwise `untitledMark`.
    /// - Parameter isFirst: Whether this is the book's first chapter (`BookDocument.chapters.first`).
    public static func label(for chapter: Chapter, isFirst: Bool, bookTitle: String) -> String {
        heading(of: chapter) ?? (isFirst ? bookTitle : untitledMark)
    }
}
