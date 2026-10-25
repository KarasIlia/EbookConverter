import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Finds image XObjects drawn on PDF pages and renders each placed rectangle to a JPEG/PNG asset.
///
/// Placements come from scanning the content stream (`q`, `Q`, `cm`, `Do`) with a CTM stack; images inside
/// Form XObjects are found too (the form's `/Matrix` is applied, up to `maximumFormDepth` levels). Inline
/// images (`BI … EI`) are not extracted. Rendering the page region rather than decoding the image data keeps
/// masks, decode arrays and colour spaces right, at the cost of including anything drawn over the image.
/// Clip paths and form `/BBox`es are not applied, so a clipped image reports its full placed rectangle.
public enum PDFImageExtractor {
    /// Render resolution relative to page points.
    static let renderScale: CGFloat = 2
    /// The rendered bitmap's long side is capped here (then `ImageNormalizer` keeps it as is).
    static let maxPixelSize = 1600
    static let jpegQuality = 0.85
    /// Nesting limit for Form XObjects; also guards against cyclic resources.
    static let maximumFormDepth = 4

    /// Images of at least `minimumSide` points on both sides, in page order and content-stream order within a
    /// page, with ids `img-1`, `img-2`, …. `bounds` are in visible page space, like `PDFTextLine.bounds`.
    public static func images(in document: CGPDFDocument, minimumSide: CGFloat = 60) -> [PDFPlacedImage] {
        guard let table = makeOperatorTable() else { return [] }
        defer { CGPDFOperatorTableRelease(table) }
        var result: [PDFPlacedImage] = []
        guard document.numberOfPages > 0 else { return [] }
        for pageNumber in 1...document.numberOfPages {
            guard let page = document.page(at: pageNumber) else { continue }
            let crop = page.getBoxRect(.cropBox)
            let rotation = PDFLineExtractor.normalizedRotation(Int(page.rotationAngle))
            let pageSize = rotation == 90 || rotation == 270
                ? CGSize(width: crop.height, height: crop.width) : crop.size
            var seen: [CGRect] = []
            for placement in placements(on: page, table: table) {
                let visible = PDFLineExtractor.visibleBounds(placement, crop: crop, rotation: rotation)
                guard !visible.isNull, visible.width >= minimumSide, visible.height >= minimumSide else { continue }
                // The same image painted twice at the same spot (e.g. an image and its stencil mask) counts once.
                guard !seen.contains(where: { isNearlyEqual($0, visible) }) else { continue }
                seen.append(visible)
                guard let data = render(page, region: visible, pageSize: pageSize),
                      let asset = ImageNormalizer.normalize(data, id: "img-\(result.count + 1)", maxPixelSize: maxPixelSize)
                else { continue }
                result.append(PDFPlacedImage(pageIndex: pageNumber - 1, bounds: visible, asset: asset))
            }
        }
        return result
    }

    private static func isNearlyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1 && abs(a.maxX - b.maxX) < 1 && abs(a.maxY - b.maxY) < 1
    }

    // MARK: - Content stream scanning

    /// Mutable scan state shared with the C operator callbacks through the scanner's `info` pointer.
    private final class ScanState {
        let table: CGPDFOperatorTableRef
        var ctm = CGAffineTransform.identity
        var stack: [CGAffineTransform] = []
        var formDepth = 0
        /// Image rectangles in raw (unrotated, media-box) user space.
        var placements: [CGRect] = []

        init(table: CGPDFOperatorTableRef) {
            self.table = table
        }
    }

    private static func state(_ info: UnsafeMutableRawPointer?) -> ScanState? {
        info.map { Unmanaged<ScanState>.fromOpaque($0).takeUnretainedValue() }
    }

    private static func makeOperatorTable() -> CGPDFOperatorTableRef? {
        guard let table = CGPDFOperatorTableCreate() else { return nil }
        CGPDFOperatorTableSetCallback(table, "q") { _, info in
            guard let state = PDFImageExtractor.state(info) else { return }
            state.stack.append(state.ctm)
        }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            guard let state = PDFImageExtractor.state(info), let saved = state.stack.popLast() else { return }
            state.ctm = saved
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            guard let state = PDFImageExtractor.state(info) else { return }
            // Operands are popped last-first: f e d c b a.
            var values = [CGPDFReal](repeating: 0, count: 6)
            for index in (0..<6).reversed() {
                guard CGPDFScannerPopNumber(scanner, &values[index]) else { return }
            }
            let matrix = CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
            state.ctm = matrix.concatenating(state.ctm)
        }
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            guard let state = PDFImageExtractor.state(info) else { return }
            var name: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &name), let name else { return }
            PDFImageExtractor.drawXObject(named: name, scanner: scanner, state: state)
        }
        return table
    }

    private static func placements(on page: CGPDFPage, table: CGPDFOperatorTableRef) -> [CGRect] {
        let state = ScanState(table: table)
        let stream = CGPDFContentStreamCreateWithPage(page)
        defer { CGPDFContentStreamRelease(stream) }
        scan(stream, state: state)
        return state.placements
    }

    private static func scan(_ stream: CGPDFContentStreamRef, state: ScanState) {
        withExtendedLifetime(state) {
            let scanner = CGPDFScannerCreate(stream, state.table, Unmanaged.passUnretained(state).toOpaque())
            defer { CGPDFScannerRelease(scanner) }
            CGPDFScannerScan(scanner)
        }
    }

    private static func drawXObject(named name: UnsafePointer<CChar>, scanner: CGPDFScannerRef, state: ScanState) {
        let contentStream = CGPDFScannerGetContentStream(scanner)
        var stream: CGPDFStreamRef?
        var subtype: UnsafePointer<CChar>?
        guard let object = CGPDFContentStreamGetResource(contentStream, "XObject", name),
              CGPDFObjectGetValue(object, .stream, &stream), let stream,
              let dictionary = CGPDFStreamGetDictionary(stream),
              CGPDFDictionaryGetName(dictionary, "Subtype", &subtype), let subtype else { return }

        switch String(cString: subtype) {
        case "Image":
            // An image fills the unit square of its user space.
            state.placements.append(CGRect(x: 0, y: 0, width: 1, height: 1).applying(state.ctm))
        case "Form" where state.formDepth < maximumFormDepth:
            // A form runs like `q <Matrix> cm … Q` with its own resources (falling back to the parent's) and
            // its own `q`/`Q` stack, so a malformed form with extra `Q`s cannot unwind the parent's states.
            let savedCTM = state.ctm
            let savedStack = state.stack
            state.stack = []
            state.ctm = formMatrix(dictionary).concatenating(state.ctm)
            state.formDepth += 1
            var resources: CGPDFDictionaryRef?
            _ = CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources)
            // Without `/Resources` (legacy inheritance) the form dictionary stands in: it has no `/XObject`
            // entry, so lookups fall through to the parent stream's resources.
            let formStream = CGPDFContentStreamCreateWithStream(stream, resources ?? dictionary, contentStream)
            scan(formStream, state: state)
            CGPDFContentStreamRelease(formStream)
            state.formDepth -= 1
            state.stack = savedStack
            state.ctm = savedCTM
        default:
            break
        }
    }

    /// A form's `/Matrix`, identity when absent or malformed.
    private static func formMatrix(_ dictionary: CGPDFDictionaryRef) -> CGAffineTransform {
        var array: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dictionary, "Matrix", &array), let array, CGPDFArrayGetCount(array) == 6 else {
            return .identity
        }
        var values = [CGPDFReal](repeating: 0, count: 6)
        for index in 0..<6 {
            guard CGPDFArrayGetNumber(array, index, &values[index]) else { return .identity }
        }
        return CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
    }

    // MARK: - Rendering

    /// Renders `region` (visible page space) of `page` at `renderScale` and encodes it as JPEG.
    private static func render(_ page: CGPDFPage, region: CGRect, pageSize: CGSize) -> Data? {
        let scale = min(renderScale, CGFloat(maxPixelSize) / max(region.width, region.height))
        let width = Int((region.width * scale).rounded())
        let height = Int((region.height * scale).rounded())
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -region.minX, y: -region.minY)
        // Maps the crop box, rotated, onto the visible page rect — the space `region` is in.
        context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: pageSize), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
