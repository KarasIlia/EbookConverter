import Testing
import PDFKit
@testable import EbookCore

struct CoverDetectorTests {
    private static func text(_ count: Int) -> Block {
        .paragraph([InlineRun(String(repeating: "a", count: count))])
    }

    private static func book(_ chapters: [Chapter]) -> BookDocument {
        BookDocument(metadata: BookMetadata(title: "T", author: "A", language: "en"), chapters: chapters)
    }

    @Test func firstImageBeforeTextIsCover() {
        let image = FixtureFactory.pngImage(width: 600, height: 800, id: "cover")
        let other = FixtureFactory.pngImage(width: 600, height: 800, id: "other")
        var document = Self.book([Chapter(title: "One", blocks: [Self.text(50), .image(image), Self.text(500), .image(other)])])
        let cover = CoverDetector.extractCover(from: &document)
        #expect(cover?.id == "cover")
        #expect(document.allImages.map(\.id) == ["other"])
        #expect(document.chapters[0].blocks.count == 3)
    }

    @Test func imageAfterLongTextIsNotCover() {
        let image = FixtureFactory.pngImage(width: 600, height: 800)
        var document = Self.book([Chapter(blocks: [Self.text(250), .image(image)])])
        #expect(CoverDetector.extractCover(from: &document) == nil)
        #expect(document.allImages.count == 1)
    }

    @Test func smallImageIsNotCover() {
        let image = FixtureFactory.pngImage(width: 600, height: 299)
        var document = Self.book([Chapter(blocks: [.image(image), Self.text(10)])])
        #expect(CoverDetector.extractCover(from: &document) == nil)
        #expect(document.allImages.count == 1)
    }

    @Test func pdfLargeFirstPageImageIsCover() {
        let image = FixtureFactory.pngImage(width: 600, height: 800)
        var document = Self.book([Chapter(blocks: [Self.text(500), .image(image)])])
        #expect(CoverDetector.extractCover(from: &document, pdfFirstPageImageCoverage: 0.4) == nil)
        #expect(CoverDetector.extractCover(from: &document, pdfFirstPageImageCoverage: 0.7) != nil)
        #expect(document.allImages.isEmpty)
    }

    @Test func emptyChapterDroppedAfterRemoval() {
        let image = FixtureFactory.pngImage(width: 600, height: 800)
        var document = Self.book([
            Chapter(blocks: [.image(image)]),
            Chapter(title: "Two", blocks: [Self.text(20)]),
        ])
        #expect(CoverDetector.extractCover(from: &document) != nil)
        #expect(document.chapters.map(\.title) == ["Two"])
    }

    @Test func titledChapterStaysWhenEmptied() {
        let image = FixtureFactory.pngImage(width: 600, height: 800)
        var document = Self.book([Chapter(title: "Cover", blocks: [.image(image)]), Chapter(blocks: [Self.text(20)])])
        #expect(CoverDetector.extractCover(from: &document) != nil)
        #expect(document.chapters.count == 2)
        #expect(document.chapters[0].blocks.isEmpty)
    }

    @Test func coverInNestedChapterIsRemovedAndEmptyPartDropped() {
        let image = FixtureFactory.pngImage(width: 600, height: 800)
        let part = Chapter(children: [Chapter(blocks: [.image(image)])])
        var document = Self.book([part, Chapter(title: "Two", blocks: [Self.text(20)])])
        #expect(CoverDetector.extractCover(from: &document) != nil)
        #expect(document.chapters.map(\.title) == ["Two"])
    }

    @Test func partOwnBlocksComeBeforeChildren() {
        let own = FixtureFactory.pngImage(width: 600, height: 800, id: "own")
        let nested = FixtureFactory.pngImage(width: 600, height: 800, id: "nested")
        let part = Chapter(title: "Part", blocks: [.image(own)], children: [Chapter(blocks: [.image(nested)])])
        var document = Self.book([part])
        #expect(CoverDetector.extractCover(from: &document)?.id == "own")
        #expect(document.allImages.map(\.id) == ["nested"])
    }

    @Test func pdfImporterSetsSourceCover() async throws {
        let image = FixtureImageBox(
            page: 0, rect: CGRect(x: 106, y: 200, width: 400, height: 560),
            image: FixtureFactory.pngImage(width: 400, height: 560)
        )
        let body = [
            "It was a bright cold day in April, and the clocks",
            "were striking thirteen. Winston Smith, his chin",
            "nuzzled into his breast in an effort to escape the",
            "vile wind, slipped quickly through the glass doors.",
        ].enumerated().map { index, line in
            FixtureTextBox(line, rect: CGRect(x: 72, y: 600 - Double(index) * 15, width: 450, height: 14))
        }
        let title = FixtureTextBox("A Title", rect: CGRect(x: 72, y: 100, width: 400, height: 30), fontSize: 24)
        let url = try FixtureFactory.pdf(pages: [[title], body], images: [image])
        let result = try await PDFImporter().importBook(from: url, context: ImportContext())
        #expect(result.sourceCover != nil)
        #expect(result.document.allImages.isEmpty)
    }

    @Test func pdfCandidateIDSelectsLargeImageOverEarlierLogo() {
        let logo = FixtureFactory.pngImage(width: 100, height: 100, id: "img-1")
        let large = FixtureFactory.pngImage(width: 600, height: 800, id: "img-2")
        var document = Self.book([Chapter(blocks: [.image(logo), Self.text(500), .image(large)])])
        let cover = CoverDetector.extractCover(from: &document, pdfFirstPageImageCoverage: 0.8, pdfCoverCandidateID: "img-2")
        #expect(cover?.id == "img-2")
        #expect(document.allImages.map(\.id) == ["img-1"])
    }

    /// Page 1 has well over 200 characters of text above an image; `coverage` decides.
    private func importFirstPage(imageRect: CGRect) async throws -> ImportResult {
        let lines = [
            "It was a bright cold day in April, and the clocks",
            "were striking thirteen. Winston Smith, his chin",
            "nuzzled into his breast in an effort to escape the",
            "vile wind, slipped quickly through the glass doors",
            "of Victory Mansions, though not quickly enough.",
        ]
        let text = lines.enumerated().map { index, line in
            FixtureTextBox(line, rect: CGRect(x: 72, y: 780 - Double(index) * 15, width: 450, height: 14))
        }
        let image = FixtureImageBox(page: 0, rect: imageRect, image: FixtureFactory.pngImage(width: 600, height: 800))
        let url = try FixtureFactory.pdf(pages: [text], images: [image])
        return try await PDFImporter().importBook(from: url, context: ImportContext())
    }

    @Test func pdfImporterLargeImageAfterLongTextIsCover() async throws {
        // 400 x 600 on A4 (595 x 842) is about 0.48, so use a larger one: 500 x 600 is about 0.6.
        let result = try await importFirstPage(imageRect: CGRect(x: 50, y: 50, width: 500, height: 600))
        #expect(result.sourceCover != nil)
        #expect(result.document.allImages.isEmpty)
    }

    @Test func pdfImporterSmallerImageAfterLongTextIsNotCover() async throws {
        let result = try await importFirstPage(imageRect: CGRect(x: 50, y: 50, width: 300, height: 400))
        #expect(result.sourceCover == nil)
        #expect(result.document.allImages.count == 1)
    }
}
