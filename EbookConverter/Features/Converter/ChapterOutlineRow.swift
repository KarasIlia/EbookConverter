import SwiftUI
import EbookCore

/// A sidebar row for a chapter; a part (a chapter with children) is an expandable group of its children.
struct ChapterOutlineRow: View {
    let chapter: Chapter

    @State private var isExpanded = true

    var body: some View {
        if chapter.children.isEmpty {
            ChapterTitleLabel(title: chapter.title)
                .tag(chapter.id)
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(chapter.children) { child in
                    ChapterOutlineRow(chapter: child)
                }
            } label: {
                ChapterTitleLabel(title: chapter.title)
            }
            .tag(chapter.id)
        }
    }
}
