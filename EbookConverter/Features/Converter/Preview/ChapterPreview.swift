import SwiftUI
import EbookCore

/// Read-only rendering of one chapter from the intermediate model: its title heading, then its blocks, as exported.
struct ChapterPreview: View {
    let chapter: Chapter
    /// Lays the text out right to left (Arabic, Hebrew…), as the exported book will be.
    let isRightToLeft: Bool

    @State private var position = ScrollPosition(edge: .top)
    @State private var imageCache = PreviewImageCache()

    var body: some View {
        ScrollView {
            // No gap between paragraphs, as in the exported book; headings and images bring their own padding.
            LazyVStack(alignment: .leading, spacing: 0) {
                // The writers put the chapter title above its text.
                if let heading = TableOfContentsLabel.heading(of: chapter) {
                    Text(heading)
                        .font(.title.bold())
                        .padding(.bottom)
                }
                ForEach(chapter.blocks.enumerated(), id: \.offset) { _, block in
                    BlockView(block: block, imageCache: imageCache)
                }
            }
            .font(.body.leading(.loose))
            .fontDesign(.serif)
            .frame(maxWidth: ConverterLayout.previewTextColumnWidth, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity)
        }
        .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
        .scrollPosition($position)
        .onChange(of: chapter.id) {
            position.scrollTo(edge: .top)
        }
    }
}

#Preview("Right to left") {
    ChapterPreview(
        chapter: Chapter(title: "الفصل الأول", blocks: [
            .heading(level: 1, runs: [InlineRun("الفصل الأول")]),
            .paragraph([
                InlineRun("هذا "), InlineRun("نص", bold: true), InlineRun(" تجريبي لمعاينة كتاب باللغة "),
                InlineRun("العربية", italic: true), InlineRun(" من اليمين إلى اليسار."),
            ]),
            .paragraph([InlineRun(String(repeating: "كان يا ما كان في قديم الزمان. ", count: 12))]),
        ]),
        isRightToLeft: true
    )
}
