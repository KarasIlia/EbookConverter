import Testing
import Foundation
@testable import EbookCore

@Suite struct MarkdownImporterTests {
    private func folder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func importBook(_ markdown: String, name: String = "doc.md", in dir: URL? = nil, context: ImportContext = ImportContext()) async throws -> ImportResult {
        let dir = try dir ?? folder()
        let url = dir.appending(path: name)
        try Data(markdown.utf8).write(to: url)
        return try await MarkdownImporter().importBook(from: url, context: context)
    }

    private static let english = "The quick brown fox jumps over the lazy dog while the sun is setting slowly behind the distant hills."

    @Test func headersBecomeChapters() async throws {
        let result = try await importBook("## A\n\ntext **bold**\n\n## B\n\ntext")
        #expect(result.document.chapters.map(\.title) == ["A", "B"])
        let runs = try #require(result.document.chapters.first?.blocks.compactMap { block -> [InlineRun]? in
            if case .paragraph(let runs) = block { runs } else { nil }
        }.first)
        #expect(runs.contains { $0.text == "bold" && $0.isBold })
        #expect(runs.contains { $0.text.hasPrefix("text") && !$0.isBold })
    }

    @Test func singleTopHeaderIsTitle() async throws {
        let result = try await importBook("# Книга\n\n## Глава\n\nтекст")
        #expect(result.document.metadata.title == "Книга")
        #expect(result.document.chapters.map(\.title) == ["Глава"])
    }

    @Test func titleFallsBackToFilename() async throws {
        let result = try await importBook("## A\n\ntext\n\n## B\n\ntext", name: "My_Book.md")
        #expect(result.document.metadata.title == "My Book")
    }

    @Test func multipleTopHeadersAreNotTitle() async throws {
        let result = try await importBook("# One\n\ntext\n\n# Two\n\ntext", name: "x.md")
        #expect(result.document.metadata.title == "x")
        #expect(result.document.chapters.map(\.title) == ["One", "Two"])
    }

    @Test func headingEndingWithColonStillHeading() async throws {
        let result = try await importBook("## Note:\n\ntext\n\n## Other\n\ntext")
        #expect(result.document.chapters.map(\.title) == ["Note:", "Other"])
    }

    @Test func italicAndNestedStyles() async throws {
        let result = try await importBook("## A\n\n*it* and ***both***")
        let runs = try #require(result.document.chapters.first?.blocks.compactMap { block -> [InlineRun]? in
            if case .paragraph(let runs) = block { runs } else { nil }
        }.first)
        #expect(runs.contains { $0.text == "it" && $0.isItalic && !$0.isBold })
        #expect(runs.contains { $0.text == "both" && $0.isItalic && $0.isBold })
    }

    @Test func localImageLoadedWhenReadable() async throws {
        let dir = try folder()
        try FixtureFactory.pngImage(width: 20, height: 10).data.write(to: dir.appending(path: "pic.png"))
        let result = try await importBook("## A\n\nbefore\n\n![alt](pic.png)\n\nafter", in: dir)
        let images = result.document.allImages
        #expect(images.count == 1)
        #expect(images.first?.id == "img-1")
        #expect(images.first?.pixelWidth == 20)
        #expect(result.warnings.isEmpty || result.warnings == [.languageUndetermined])
    }

    @Test func imageIdsAreSequential() async throws {
        let dir = try folder()
        try FixtureFactory.pngImage(width: 20, height: 10).data.write(to: dir.appending(path: "a b.png"))
        let result = try await importBook("## A\n\n![](a%20b.png)\n\n![](<a b.png>)", in: dir)
        #expect(result.document.allImages.map(\.id) == ["img-1", "img-2"])
    }

    @Test func remoteImageCountedAndSkipped() async throws {
        let result = try await importBook("## A\n\n![x](https://example.com/a.png)\n\n![y](http://example.com/b.png)\n\ntext")
        #expect(result.document.allImages.isEmpty)
        #expect(result.warnings.contains(.remoteImagesSkipped(count: 2)))
    }

    @Test func missingImageWithAccessibleFolderIsUnavailable() async throws {
        let dir = try folder()
        let result = try await importBook("## A\n\n![x](nope.png)", in: dir, context: ImportContext(accessibleFolder: dir))
        #expect(result.warnings.contains(.imagesUnavailable(count: 1)))
        #expect(!result.warnings.contains { if case .imagesNeedFolderAccess = $0 { true } else { false } })
    }

    @Test func missingImageWithoutFolderNeedsAccess() async throws {
        let dir = try folder()
        let result = try await importBook("## A\n\n![x](nope.png)\n\n![y](nope2.png)", in: dir)
        let needs = result.warnings.filter { if case .imagesNeedFolderAccess = $0 { true } else { false } }
        #expect(needs.count == 1)
    }

    @Test func languageDetectedOrUndetermined() async throws {
        let result = try await importBook("## A\n\n\(Self.english)")
        #expect(result.document.metadata.language == "en")
        let unknown = try await importBook("## A\n\n12 34")
        #expect(unknown.document.metadata.language == "und")
        #expect(unknown.warnings.contains(.languageUndetermined))
    }

    @Test func emptyFileThrows() async throws {
        await #expect(throws: ImportError.emptyDocument) {
            _ = try await importBook("  \n\n")
        }
    }

    @Test func listItemsKeepMarkers() async throws {
        let result = try await importBook("## A\n\n- one\n- two\n\n1. first\n2. second")
        let texts = result.document.chapters.flatMap(\.blocks).compactMap { block -> String? in
            if case .paragraph(let runs) = block { runs.map(\.text).joined() } else { nil }
        }
        #expect(texts == ["• one", "• two", "1. first", "2. second"])
    }
}
