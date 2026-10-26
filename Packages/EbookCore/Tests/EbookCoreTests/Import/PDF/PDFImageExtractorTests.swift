import Testing
import CoreGraphics
import ImageIO
import PDFKit
@testable import EbookCore

struct PDFImageExtractorTests {
    private static func cgDocument(_ url: URL) throws -> CGPDFDocument {
        try #require(CGPDFDocument(url as CFURL))
    }

    private static func expectRect(_ actual: CGRect?, _ expected: CGRect, tolerance: CGFloat = 1) {
        guard let actual else {
            Issue.record("No rect, expected \(expected)")
            return
        }
        #expect(abs(actual.minX - expected.minX) <= tolerance, "\(actual) vs \(expected)")
        #expect(abs(actual.minY - expected.minY) <= tolerance, "\(actual) vs \(expected)")
        #expect(abs(actual.width - expected.width) <= tolerance, "\(actual) vs \(expected)")
        #expect(abs(actual.height - expected.height) <= tolerance, "\(actual) vs \(expected)")
    }

    /// `true` when pixels just inside every corner of the rendered asset are the fixture image's red,
    /// i.e. the rendered region matches the placed image rather than an offset part of the page.
    private static func cornersAreRed(_ asset: ImageAsset) -> Bool {
        guard let source = CGImageSourceCreateWithData(asset.data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return false }
        let insetX = max(1, width / 20), insetY = max(1, height / 20)
        let corners = [(insetX, insetY), (width - 1 - insetX, insetY), (insetX, height - 1 - insetY), (width - 1 - insetX, height - 1 - insetY)]
        return corners.allSatisfy { x, y in
            let offset = (y * width + x) * 4
            return pixels[offset] > 150 && pixels[offset + 1] < 110 && pixels[offset + 2] < 110
        }
    }

    private static func imageBox(_ rect: CGRect, page: Int = 0) -> FixtureImageBox {
        FixtureImageBox(page: page, rect: rect, image: FixtureFactory.pngImage(width: 40, height: 30))
    }

    /// Lines of distinct prose stacked downwards from `top` at `x`.
    private static func textBoxes(_ lines: [String], x: Double = 72, top: Double, width: Double = 450) -> [FixtureTextBox] {
        lines.enumerated().map { index, text in
            FixtureTextBox(text, rect: CGRect(x: x, y: top - Double(index) * 15, width: width, height: 14))
        }
    }

    // MARK: - Extraction

    @Test func findsPlacedImage() throws {
        let rect = CGRect(x: 100, y: 400, width: 200, height: 150)
        let url = try FixtureFactory.pdf(pages: [[]], images: [Self.imageBox(rect)])
        let images = PDFImageExtractor.images(in: try Self.cgDocument(url))
        #expect(images.count == 1)
        let image = try #require(images.first)
        #expect(image.pageIndex == 0)
        Self.expectRect(image.bounds, rect)
        #expect(abs(image.asset.pixelWidth - 400) <= 2)
        #expect(abs(image.asset.pixelHeight - 300) <= 2)
        #expect(image.asset.contentType == .jpeg || image.asset.contentType == .png)
        #expect(image.asset.id == "img-1")
        #expect(Self.cornersAreRed(image.asset))
    }

    @Test func skipsTinyImages() throws {
        let url = try FixtureFactory.pdf(pages: [[]], images: [Self.imageBox(CGRect(x: 100, y: 400, width: 20, height: 20))])
        #expect(PDFImageExtractor.images(in: try Self.cgDocument(url)).isEmpty)
    }

    @Test func numbersImagesInDocumentOrder() throws {
        let url = try FixtureFactory.pdf(pages: [[], []], images: [
            Self.imageBox(CGRect(x: 100, y: 600, width: 100, height: 100), page: 0),
            Self.imageBox(CGRect(x: 100, y: 200, width: 100, height: 100), page: 0),
            Self.imageBox(CGRect(x: 100, y: 400, width: 100, height: 100), page: 1),
        ])
        let images = PDFImageExtractor.images(in: try Self.cgDocument(url))
        #expect(images.map(\.asset.id) == ["img-1", "img-2", "img-3"])
        #expect(images.map(\.pageIndex) == [0, 0, 1])
    }

    /// A hand-written one-page PDF: the page draws Form `/Fm1` (matrix 0.5 scale, offset 50,-100), whose own
    /// resources hold a 2x2 red image `/Im1` drawn at 200x150 from (100, 400). CoreGraphics flattens drawn
    /// pages, so a form has to be written by hand.
    /// `pageContent` may also draw `/Im1` directly.
    private static func formWrappedImagePDF(
        formContent: String = "q 200 0 0 150 100 400 cm /Im1 Do Q", pageContent: String = "q /Fm1 Do Q"
    ) throws -> URL {
        let objects: [Data] = [
            Data("<< /Type /Catalog /Pages 2 0 R >>".utf8),
            Data("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".utf8),
            Data("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /XObject << /Fm1 4 0 R /Im1 5 0 R >> >> /Contents 6 0 R >>".utf8),
            Data("<< /Type /XObject /Subtype /Form /BBox [0 0 595 842] /Matrix [0.5 0 0 0.5 50 -100] /Resources << /XObject << /Im1 5 0 R >> >> /Length \(formContent.utf8.count) >>\nstream\n\(formContent)\nendstream".utf8),
            Data("<< /Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Length 12 >>\nstream\n".utf8)
                + Data([UInt8](repeating: 0, count: 4).flatMap { _ in [0xCC, 0x33, 0x33] }) + Data("\nendstream".utf8),
            Data("<< /Length \(pageContent.utf8.count) >>\nstream\n\(pageContent)\nendstream".utf8),
        ]
        var pdf = Data("%PDF-1.4\n".utf8)
        var offsets: [Int] = []
        for (index, body) in objects.enumerated() {
            offsets.append(pdf.count)
            pdf += Data("\(index + 1) 0 obj\n".utf8) + body + Data("\nendobj\n".utf8)
        }
        let xref = pdf.count
        pdf += Data("xref\n0 \(objects.count + 1)\n0000000000 65535 f \n".utf8)
        for offset in offsets {
            let padded = String(repeating: "0", count: max(0, 10 - String(offset).count)) + String(offset)
            pdf += Data("\(padded) 00000 n \n".utf8)
        }
        pdf += Data("trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n".utf8)
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "form.pdf")
        try pdf.write(to: url)
        return url
    }

    @Test func findsImageInsideFormXObject() throws {
        let document = try Self.cgDocument(try Self.formWrappedImagePDF())
        let images = PDFImageExtractor.images(in: document)
        #expect(images.count == 1)
        Self.expectRect(images.first?.bounds, CGRect(x: 100, y: 100, width: 100, height: 75))
        #expect(images.first.map { Self.cornersAreRed($0.asset) } == true)
    }

    /// A malformed form popping more states than it pushed must not unwind the page's own `q` stack.
    @Test func formWithExtraRestoreKeepsParentStack() throws {
        let url = try Self.formWrappedImagePDF(
            formContent: "Q Q",
            pageContent: "q q 0.5 0 0 0.5 0 0 cm /Fm1 Do Q Q 200 0 0 150 100 400 cm /Im1 Do"
        )
        let images = PDFImageExtractor.images(in: try Self.cgDocument(url))
        #expect(images.count == 1)
        Self.expectRect(images.first?.bounds, CGRect(x: 100, y: 400, width: 200, height: 150))
    }

    @Test func rotatedPageBoundsUseVisiblePageSpace() throws {
        let source = try FixtureFactory.pdf(pages: [[]], images: [Self.imageBox(CGRect(x: 100, y: 400, width: 200, height: 150))])
        let document = try #require(PDFDocument(url: source))
        document.page(at: 0)?.rotation = 90
        let url = source.deletingLastPathComponent().appending(path: "rotated.pdf")
        #expect(document.write(to: url))

        let images = PDFImageExtractor.images(in: try Self.cgDocument(url))
        let image = try #require(images.first)
        // Same mapping as PDFLineExtractor: (x, y, w, h) -> (y, cropWidth - (x + w), h, w).
        Self.expectRect(image.bounds, CGRect(x: 400, y: 295, width: 150, height: 200))
        #expect(abs(image.asset.pixelWidth - 300) <= 2)
        #expect(abs(image.asset.pixelHeight - 400) <= 2)
        #expect(Self.cornersAreRed(image.asset))
    }

    // MARK: - Importer placement

    @Test func importerPlacesImageBetweenParagraphs() async throws {
        let above = [
            "It was a bright cold day in April, and the clocks",
            "were striking thirteen and nobody looked up.",
            "Outside, even through the shut window-pane, the",
            "world looked cold, and down in the street little",
            "eddies of wind were whirling dust and torn paper.",
        ]
        let below = [
            "The hallway smelt of boiled cabbage and old rag",
            "mats, and the lift had not worked for weeks.",
        ]
        let url = try FixtureFactory.pdf(
            pages: [Self.textBoxes(above, top: 700) + Self.textBoxes(below, top: 300)],
            images: [Self.imageBox(CGRect(x: 100, y: 400, width: 200, height: 150))]
        )
        let result = try await PDFImporter().importBook(from: url, context: ImportContext())
        let blocks = result.document.chapters.flatMap(\.blocks)
        #expect(blocks.count == 3)
        #expect(blocks.first == .paragraph([InlineRun(above.joined(separator: " "))]))
        if case .image(let asset) = blocks.dropFirst().first {
            #expect(asset.id == "img-1")
        } else {
            Issue.record("Expected an image second, got \(blocks)")
        }
        #expect(blocks.last == .paragraph([InlineRun(below.joined(separator: " "))]))
        #expect(result.document.allImages.count == 1)
    }

    /// An image at the top of the right column comes after the whole left column, before the right column's text.
    @Test func importerPlacesImageInItsColumn() async throws {
        let left = [
            "It was a bright cold day in", "April, and the clocks were", "striking thirteen. Winston",
            "Smith, his chin nuzzled into", "his breast, slipped quickly", "through the glass doors.",
            "Outside the window the world looked cold and grey,", "and nobody was walking in the street.",
        ]
        let right = [
            "The hallway smelt of boiled", "cabbage and old rag mats.", "At one end of it a poster",
            "had been tacked to the wall.",
        ]
        let url = try FixtureFactory.pdf(
            pages: [Self.textBoxes(left, x: 72, top: 700, width: 200) + Self.textBoxes(right, x: 320, top: 500, width: 200)],
            images: [Self.imageBox(CGRect(x: 320, y: 560, width: 200, height: 150))]
        )
        let blocks = try await PDFImporter().importBook(from: url, context: ImportContext()).document.chapters.flatMap(\.blocks)
        #expect(blocks.count == 3)
        #expect(blocks.first == .paragraph([InlineRun(left.joined(separator: " "))]))
        if case .image = blocks.dropFirst().first {} else { Issue.record("Expected an image second, got \(blocks)") }
        #expect(blocks.last == .paragraph([InlineRun(right.joined(separator: " "))]))
    }

    /// A page-covering image under a full text page is a background or scan layer, not an illustration.
    @Test func importerDropsFullPageImageBehindLongText() async throws {
        let lines = [
            "It was a bright cold day in April, and the clocks",
            "were striking thirteen. Winston Smith, his chin",
            "nuzzled into his breast in an effort to escape the",
            "vile wind, slipped quickly through the glass doors",
            "of Victory Mansions, though not quickly enough.",
        ]
        let url = try FixtureFactory.pdf(
            pages: [Self.textBoxes(lines, top: 700)],
            images: [Self.imageBox(CGRect(x: 0, y: 0, width: 595, height: 842))]
        )
        let result = try await PDFImporter().importBook(from: url, context: ImportContext())
        #expect(result.document.allImages.isEmpty)
        #expect(result.document.chapters.flatMap(\.blocks).count == 1)
    }

    /// A page-covering image with only a little text is not dropped as a background; as the first image it becomes the source cover.
    @Test func importerExtractsFullPageImageWithShortTextAsCover() async throws {
        let body = [
            "It was a bright cold day in April, and the clocks",
            "were striking thirteen and nobody looked up.",
        ]
        let url = try FixtureFactory.pdf(
            pages: [Self.textBoxes(["The Cover Title Of The Book"], top: 700), Self.textBoxes(body, top: 700)],
            images: [Self.imageBox(CGRect(x: 0, y: 0, width: 595, height: 842), page: 0)]
        )
        let result = try await PDFImporter().importBook(from: url, context: ImportContext())
        #expect(result.sourceCover != nil)
        #expect(result.document.allImages.isEmpty)
    }

    @Test func importerKeepsImagesOfTextlessPagesInPageOrder() async throws {
        let first = [
            "It was a bright cold day in April, and the clocks", "were striking thirteen and nobody looked up.",
            "Outside, even through the shut window-pane, the",
            "world looked cold, and down in the street little",
            "eddies of wind were whirling dust and torn paper.",
        ]
        let third = ["The hallway smelt of boiled cabbage and old rag", "mats, and the lift had not worked for weeks."]
        let url = try FixtureFactory.pdf(
            pages: [Self.textBoxes(first, top: 700), [], Self.textBoxes(third, top: 700)],
            images: [Self.imageBox(CGRect(x: 100, y: 300, width: 300, height: 300), page: 1)]
        )
        let blocks = try await PDFImporter().importBook(from: url, context: ImportContext()).document.chapters.flatMap(\.blocks)
        #expect(blocks.count == 3)
        if case .image = blocks.dropFirst().first {} else { Issue.record("Expected an image second, got \(blocks)") }
    }
}
