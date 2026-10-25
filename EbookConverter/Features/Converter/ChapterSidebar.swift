import SwiftUI
import EbookCore

/// Table of contents of the opened book; selecting a chapter shows it in the preview.
struct ChapterSidebar: View {
    let chapters: [Chapter]
    @Binding var selection: Chapter.ID?

    var body: some View {
        List(selection: $selection) {
            ForEach(chapters) { chapter in
                ChapterOutlineRow(chapter: chapter)
            }
        }
        .listStyle(.sidebar)
    }
}
