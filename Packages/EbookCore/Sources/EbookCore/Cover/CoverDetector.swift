/// Finds a cover image at the start of an imported document and moves it out of the body.
public enum CoverDetector {
    /// The image counts as a cover only when it comes before this many characters of text.
    static let textLimit = 200
    /// Smallest allowed short side of a cover, in pixels.
    static let minimumShortSide = 300
    /// A first-page image covering at least this share of the page is a cover regardless of preceding text.
    static let pdfCoverageThreshold = 0.5

    /// Removes and returns the cover: the first image block of the book (reading order, a part's own blocks
    /// before its children) if fewer than 200 text characters precede it, or, when `pdfFirstPageImageCoverage`
    /// is at least 0.5, regardless of preceding text. The first image decides; one with a short side under
    /// 300 px is not a cover and nothing is removed. A chapter left with no blocks, no children and no title
    /// is dropped; titled chapters stay. Remaining image ids are not renumbered.
    public static func extractCover(
        from document: inout BookDocument, pdfFirstPageImageCoverage: Double? = nil
    ) -> ImageAsset? {
        let ignoresText = (pdfFirstPageImageCoverage ?? 0) >= pdfCoverageThreshold
        var characters = 0
        var finished = false
        var cover: ImageAsset?

        /// Returns `true` when the chapter ended up empty and untitled, so the caller drops it.
        func process(_ chapter: inout Chapter) -> Bool {
            var index = 0
            while index < chapter.blocks.count, !finished {
                switch chapter.blocks[index] {
                case .heading(_, let runs), .paragraph(let runs):
                    characters += runs.reduce(0) { $0 + $1.text.count }
                    if characters >= textLimit, !ignoresText { finished = true }
                case .image(let asset):
                    finished = true
                    if min(asset.pixelWidth, asset.pixelHeight) >= minimumShortSide {
                        cover = asset
                        chapter.blocks.remove(at: index)
                    }
                    continue
                }
                index += 1
            }
            var childIndex = 0
            while childIndex < chapter.children.count, !finished {
                if process(&chapter.children[childIndex]) {
                    chapter.children.remove(at: childIndex)
                } else {
                    childIndex += 1
                }
            }
            return cover != nil && chapter.blocks.isEmpty && chapter.children.isEmpty && chapter.title == nil
        }

        var chapterIndex = 0
        while chapterIndex < document.chapters.count, !finished {
            if process(&document.chapters[chapterIndex]) {
                document.chapters.remove(at: chapterIndex)
            } else {
                chapterIndex += 1
            }
        }
        return cover
    }
}
