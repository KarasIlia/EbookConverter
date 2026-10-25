import Testing
import Foundation
import UniformTypeIdentifiers
@testable import EbookCore

@Suite struct ModelTests {
    private func image(_ id: String) -> ImageAsset {
        ImageAsset(id: id, data: Data([1]), contentType: .png, pixelWidth: 1, pixelHeight: 1)
    }

    @Test func leafChaptersFlattensParts() {
        let a = Chapter(title: "A")
        let b = Chapter(title: "B")
        let part = Chapter(title: "Part", children: [a, b])
        let c = Chapter(title: "C")
        let doc = BookDocument(
            metadata: BookMetadata(title: "T", author: "X", language: "en"),
            chapters: [part, c])
        #expect(doc.leafChapters.map(\.title) == ["A", "B", "C"])
    }

    @Test func allImagesCollectsNested() {
        let child = Chapter(title: "Child", blocks: [.image(image("i1")), .paragraph([InlineRun("x")])])
        let part = Chapter(title: "Part", children: [child])
        let flat = Chapter(title: "Flat", blocks: [.image(image("i2"))])
        let doc = BookDocument(
            metadata: BookMetadata(title: "T", author: "X", language: "en"),
            chapters: [part, flat])
        #expect(doc.allImages.map(\.id) == ["i1", "i2"])
    }

    @Test func plainTextJoinsParagraphs() {
        let chapter = Chapter(blocks: [
            .paragraph([InlineRun("a"), InlineRun("b", bold: true)]),
            .paragraph([InlineRun("c")]),
        ])
        #expect(chapter.plainText == "ab\nc")
    }

    @Test func rightToLeftDetection() {
        #expect(BookMetadata(title: "", author: "", language: "ar").isRightToLeft)
        #expect(BookMetadata(title: "", author: "", language: "he").isRightToLeft)
        #expect(!BookMetadata(title: "", author: "", language: "ru").isRightToLeft)
        #expect(!BookMetadata(title: "", author: "", language: "und").isRightToLeft)
    }

    @Test func outputFormatProperties() {
        #expect(OutputFormat.epub.fileExtension == "epub")
        #expect(OutputFormat.fb2.fileExtension == "fb2")
        #expect(OutputFormat.epub.contentType == .epub)
        #expect(OutputFormat.fb2.contentType.identifier == "ru.fictionbook.fb2")
    }
}
