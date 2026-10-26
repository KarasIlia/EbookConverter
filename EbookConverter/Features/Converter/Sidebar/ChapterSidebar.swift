import SwiftUI
import EbookCore

/// Table of contents of the opened book, labelled as in the exported book; selecting a chapter shows it in the preview.
struct ChapterSidebar: View {
    let chapters: [Chapter]
    /// Title the exported book carries; it labels an untitled first chapter.
    let bookTitle: String
    @Binding var selection: Chapter.ID?

    var body: some View {
        List(selection: $selection) {
            ForEach(chapters) { chapter in
                ChapterOutlineRow(chapter: chapter, isFirst: chapter.id == chapters.first?.id, bookTitle: bookTitle)
            }
        }
        .listStyle(.sidebar)
    }
}
