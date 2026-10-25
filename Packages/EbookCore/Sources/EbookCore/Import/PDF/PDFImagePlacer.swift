import CoreGraphics

/// Inserts placed images into the reflowed paragraph stream, at paragraph boundaries.
///
/// An image is placed relative to the lines of its own column: the page's lines that overlap it horizontally
/// (all of the page's lines when none do, e.g. an image in the margin). It goes right before the first such
/// line below it in reading order, otherwise after the last such line above it — so in a two-column page an
/// image at the top of the right column follows the whole left column even under a full-width title. A line
/// in the middle of a paragraph puts the image after that paragraph. Images on pages without text follow the
/// previous pages' text. Images are then renumbered `img-1`, `img-2`, … in final reading order.
enum PDFImagePlacer {
    /// An image covering at least this share of its page's area is a background candidate.
    static let backgroundAreaShare = 0.9
    /// Pages with more extracted characters than this treat a page-covering image as a background or scan
    /// layer and drop it; pages with less text (covers, full-page illustrations) keep it.
    static let backgroundTextCharacters = 200

    /// `images` without page-covering background layers behind text-heavy pages. `lines` are all extracted
    /// lines (before running-header removal); they also supply each page's visible size.
    static func removingBackgrounds(_ images: [PDFPlacedImage], lines: [PDFTextLine]) -> [PDFPlacedImage] {
        var characters: [Int: Int] = [:]
        var pageSizes: [Int: CGSize] = [:]
        for line in lines {
            characters[line.pageIndex, default: 0] += line.text.count
            pageSizes[line.pageIndex] = line.pageSize
        }
        return images.filter { image in
            guard let size = pageSizes[image.pageIndex],
                  characters[image.pageIndex, default: 0] > backgroundTextCharacters else { return true }
            let area = image.bounds.width * image.bounds.height
            return area < backgroundAreaShare * size.width * size.height
        }
    }

    static func merged(_ located: [PDFReflow.Located], images: [PDFPlacedImage]) -> [PDFFlowItem] {
        // Lines in reading order with the index of the paragraph they belong to.
        let lines = located.enumerated().flatMap { index, item in item.lines.map { (paragraph: index, line: $0) } }
        let sorted = images.sorted { lhs, rhs in
            if lhs.pageIndex != rhs.pageIndex { return lhs.pageIndex < rhs.pageIndex }
            if lhs.bounds.maxY != rhs.bounds.maxY { return lhs.bounds.maxY > rhs.bounds.maxY }
            return lhs.bounds.minX < rhs.bounds.minX
        }
        // Images to emit after paragraph `key`; -1 is before the first paragraph.
        var imagesAfter: [Int: [PDFPlacedImage]] = [:]
        for image in sorted {
            imagesAfter[slot(for: image, lines: lines, located: located), default: []].append(image)
        }

        var result: [PDFFlowItem] = []
        var imageCount = 0
        func appendImages(after paragraph: Int) {
            for image in imagesAfter[paragraph] ?? [] {
                imageCount += 1
                result.append(.image(renumbered(image, id: "img-\(imageCount)")))
            }
        }
        appendImages(after: -1)
        for (index, item) in located.enumerated() {
            result.append(.paragraph(item))
            appendImages(after: index)
        }
        return result
    }

    /// The paragraph index after which `image` goes (-1 for the very start).
    private static func slot(
        for image: PDFPlacedImage, lines: [(paragraph: Int, line: PDFTextLine)], located: [PDFReflow.Located]
    ) -> Int {
        let page = lines.filter { $0.line.pageIndex == image.pageIndex }
        guard !page.isEmpty else {
            return lines.last { $0.line.pageIndex < image.pageIndex }?.paragraph ?? -1
        }
        let overlapping = page.filter {
            $0.line.bounds.maxX > image.bounds.minX && $0.line.bounds.minX < image.bounds.maxX
        }
        let column = overlapping.isEmpty ? page : overlapping
        if let below = column.first(where: { $0.line.bounds.midY < image.bounds.midY }) {
            let startsParagraph = located[below.paragraph].firstLine == below.line
            return startsParagraph ? below.paragraph - 1 : below.paragraph
        }
        return column.last?.paragraph ?? -1
    }

    private static func renumbered(_ image: PDFPlacedImage, id: String) -> PDFPlacedImage {
        var copy = image
        let asset = image.asset
        copy.asset = ImageAsset(
            id: id, data: asset.data, contentType: asset.contentType,
            pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight
        )
        return copy
    }
}
