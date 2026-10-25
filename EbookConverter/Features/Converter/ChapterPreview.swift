import SwiftUI
import EbookCore

/// Read-only rendering of one chapter from the intermediate model.
struct ChapterPreview: View {
    let chapter: Chapter

    @State private var position = ScrollPosition(edge: .top)
    @State private var imageCache = PreviewImageCache()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading) {
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
        .scrollPosition($position)
        .onChange(of: chapter.id) {
            position.scrollTo(edge: .top)
        }
    }
}
