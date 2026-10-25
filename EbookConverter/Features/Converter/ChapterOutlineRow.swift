import SwiftUI
import EbookCore

/// A sidebar row for a chapter; a part (a chapter with children) is an expandable group of its children.
struct ChapterOutlineRow: View {
    let chapter: Chapter
    /// Whether this is the book's first chapter (see `ChapterTitleLabel`).
    let isFirst: Bool
    let bookTitle: String

    @State private var isExpanded = true

    var body: some View {
        if chapter.children.isEmpty {
            ChapterTitleLabel(chapter: chapter, isFirst: isFirst, bookTitle: bookTitle)
                .tag(chapter.id)
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(chapter.children) { child in
                    ChapterOutlineRow(chapter: child, isFirst: false, bookTitle: bookTitle)
                }
            } label: {
                ChapterTitleLabel(chapter: chapter, isFirst: isFirst, bookTitle: bookTitle)
            }
            .tag(chapter.id)
        }
    }
}
