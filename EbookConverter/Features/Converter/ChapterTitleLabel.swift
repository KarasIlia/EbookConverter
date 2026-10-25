import SwiftUI
import EbookCore

/// A chapter's table-of-contents label, exactly as the exported book shows it; labels of untitled chapters
/// (the book title or "…") are dimmed.
struct ChapterTitleLabel: View {
    let chapter: Chapter
    /// Whether this is the book's first chapter, which the book labels with its title when it has none.
    let isFirst: Bool
    let bookTitle: String

    var body: some View {
        Text(TableOfContentsLabel.label(for: chapter, isFirst: isFirst, bookTitle: bookTitle))
            .lineLimit(2)
            .foregroundStyle(TableOfContentsLabel.heading(of: chapter) == nil ? .secondary : .primary)
    }
}
