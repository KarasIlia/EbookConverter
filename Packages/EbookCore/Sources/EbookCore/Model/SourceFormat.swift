public enum SourceFormat: Sendable, Hashable, CaseIterable {
    case txt, markdown, rtf, doc, docx, html, pdf, epub, fb2

    /// Conventional, language-neutral name of the format, e.g. "FB2" or "Markdown".
    public var displayName: String {
        switch self {
        case .markdown: "Markdown"
        default: String(describing: self).uppercased()
        }
    }

    /// The output format this source already is, if any (EPUB → EPUB, FB2 → FB2).
    public var sameOutputFormat: OutputFormat? {
        switch self {
        case .epub: .epub
        case .fb2: .fb2
        default: nil
        }
    }
}
