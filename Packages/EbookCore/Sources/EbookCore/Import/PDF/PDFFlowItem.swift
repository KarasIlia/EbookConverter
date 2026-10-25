import CoreGraphics

/// One entry of a PDF's reading-order stream: a reflowed paragraph or a placed image.
enum PDFFlowItem {
    case paragraph(PDFReflow.Located)
    case image(PDFPlacedImage)

    var pageIndex: Int {
        switch self {
        case .paragraph(let located): located.firstLine.pageIndex
        case .image(let image): image.pageIndex
        }
    }

    /// Top edge in visible page space: the first line's top for a paragraph.
    var top: CGFloat {
        switch self {
        case .paragraph(let located): located.firstLine.bounds.maxY
        case .image(let image): image.bounds.maxY
        }
    }

    var block: Block {
        switch self {
        case .paragraph(let located): .paragraph(located.paragraph.runs)
        case .image(let image): .image(image.asset)
        }
    }

    var structuredItem: StructuredItem {
        switch self {
        case .paragraph(let located): .paragraph(located.paragraph)
        case .image(let image): .image(image.asset)
        }
    }
}
