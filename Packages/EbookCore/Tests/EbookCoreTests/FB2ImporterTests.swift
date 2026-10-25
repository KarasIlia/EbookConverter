import Foundation
import Testing
@testable import EbookCore

@Suite struct FB2ImporterTests {
    // MARK: - Round trips

    @Test func fb2RoundTripKeepsStructure() async throws {
        let original = FixtureFactory.sampleDocument()
        let cover = FixtureFactory.pngImage(width: 3, height: 3, id: "cover")
        let url = try Self.write(FB2Writer().write(original, cover: cover))

        let result = try await FB2Importer().importBook(from: url, context: ImportContext())
        let imported = result.document

        #expect(imported.metadata == original.metadata)
        #expect(Self.outline(imported.chapters) == Self.outline(original.chapters))
        #expect(imported.allImages.count == original.allImages.count)
        #expect(imported.allImages.map(\.id) == ["img-1"])
        #expect(result.sourceCover != nil)
        #expect(result.warnings.isEmpty)
        #expect(zip(imported.leafChapters, original.leafChapters).allSatisfy {
            EPUBImporterTests.asWritten($1.plainText) == $0.plainText
        })
        // The part's own blocks come back from the leading untitled section.
        #expect(imported.chapters[0].plainText == "Part intro.")
        #expect(imported.chapters[0].children.map(\.title) == ["First", "Second"])
        let first = imported.chapters[0].children[0]
        #expect(first.blocks.first == .paragraph([
            InlineRun("Plain "), InlineRun("bold", bold: true), InlineRun(" and "), InlineRun("italic", italic: true), InlineRun("."),
        ]))
        // Subheadings come back as level-3 headings.
        #expect(imported.chapters[0].children[1].blocks.first == .heading(level: 3, runs: [InlineRun("Subheading")]))
    }

    @Test func epubToFb2ToEpubRoundTrip() async throws {
        let original = FixtureFactory.sampleDocument()
        let cover = FixtureFactory.pngImage(width: 3, height: 3, id: "cover")
        let epub1 = try EPUBImporterTests.write(EPUBWriter().write(original, cover: cover))
        let first = try await EPUBImporter().importBook(from: epub1, context: ImportContext())

        let fb2 = try Self.write(FB2Writer().write(first.document, cover: first.sourceCover))
        let second = try await FB2Importer().importBook(from: fb2, context: ImportContext())

        let epub2 = try EPUBImporterTests.write(EPUBWriter().write(second.document, cover: second.sourceCover))
        let third = try await EPUBImporter().importBook(from: epub2, context: ImportContext())

        #expect(third.document.chapters.count == original.chapters.count)
        #expect(Self.outline(third.document.chapters).map(\.title) == Self.outline(original.chapters).map(\.title))
        #expect(third.document.leafChapters.map(\.title) == original.leafChapters.map(\.title))
        #expect(third.document.allImages.count == original.allImages.count)
        #expect(third.sourceCover != nil)
    }

    // MARK: - Encoding

    @Test func cp1251DeclaredEncodingParsed() async throws {
        let xml = """
        <?xml version="1.0" encoding="windows-1251"?>
        <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0"><description><title-info>
        <author><first-name>Лев</first-name><last-name>Толстой</last-name></author>
        <book-title>Война и мир</book-title><lang>ru</lang></title-info></description>
        <body><section><title><p>Глава первая</p></title><p>Привет, мир!</p></section></body></FictionBook>
        """
        let data = try #require(xml.data(using: .windowsCP1251))
        let result = try await FB2Importer().importBook(from: Self.write(data), context: ImportContext())
        #expect(result.document.metadata.title == "Война и мир")
        #expect(result.document.metadata.author == "Лев Толстой")
        #expect(result.document.chapters.first?.title == "Глава первая")
        #expect(result.document.chapters.first?.plainText == "Привет, мир!")
    }

    // MARK: - Content rules

    @Test func notesBodySkipped() async throws {
        let result = try await Self.importFB2("""
        <body><section><title><p>Main</p></title><p>Text<a l:href="#n1">[1]</a>.</p></section></body>
        <body name="notes"><section id="n1"><title><p>1</p></title><p>The note.</p></section></body>
        """)
        #expect(result.document.chapters.count == 1)
        #expect(!result.document.chapters[0].plainText.contains("The note."))
    }

    @Test func notesBodyBeforeMainBodyIsStillSkipped() async throws {
        let result = try await Self.importFB2("""
        <body name="notes"><section><p>The note.</p></section></body>
        <body><section><title><p>Main</p></title><p>Text.</p></section></body>
        """)
        #expect(result.document.chapters.map(\.title) == ["Main"])
    }

    @Test func deeperSectionsAreFlattenedWithLevelThreeHeadings() async throws {
        let result = try await Self.importFB2("""
        <body><section><title><p>Part</p></title>
          <section><title><p>Chapter</p></title><p>A.</p>
            <section><title><p>Deep</p></title><p>B.</p>
              <section><title><p>Deeper</p></title><p>C.</p></section>
            </section>
          </section>
        </section></body>
        """)
        let part = try #require(result.document.chapters.first)
        #expect(part.title == "Part")
        #expect(part.children.map(\.title) == ["Chapter"])
        #expect(part.children[0].children.isEmpty)
        #expect(part.children[0].blocks == [
            .paragraph([InlineRun("A.")]),
            .heading(level: 3, runs: [InlineRun("Deep")]), .paragraph([InlineRun("B.")]),
            .heading(level: 3, runs: [InlineRun("Deeper")]), .paragraph([InlineRun("C.")]),
        ])
    }

    @Test func bodyContentBeforeSectionsBecomesLeadingChapter() async throws {
        let result = try await Self.importFB2("""
            <body><title><p>Book</p></title><epigraph><p>Motto.</p></epigraph><p>Opening words.</p>
            <section><title><p>One</p></title><p>Text.</p></section></body>
            """)
        #expect(result.document.chapters.map(\.title) == [nil, "One"])
        #expect(result.document.chapters.first?.plainText == "Motto.\nOpening words.")
    }

    @Test func bodyWithOnlyTitleAndSectionsHasNoLeadingChapter() async throws {
        let result = try await Self.importFB2("""
            <body><title><p>Book</p></title><section><title><p>One</p></title><p>Text.</p></section></body>
            """)
        #expect(result.document.chapters.map(\.title) == ["One"])
    }

    @Test func titledEmptySectionsAreKept() async throws {
        let result = try await Self.importFB2("""
            <body><section><title><p>Authors</p></title><empty-line/></section><section><empty-line/></section>
            <section><title><p>One</p></title><p>Text.</p></section></body>
            """)
        #expect(result.document.chapters.map(\.title) == ["Authors", "One"])
    }

    @Test func titledEmptyChapterSurvivesRoundTrips() async throws {
        let original = BookDocument(
            metadata: BookMetadata(title: "Book", author: "A B", language: "en"),
            chapters: [
                Chapter(title: "Authors"),
                Chapter(title: "One", blocks: [.paragraph([InlineRun("Text.")])]),
            ]
        )
        let fb2 = try await FB2Importer().importBook(from: Self.write(FB2Writer().write(original, cover: nil)), context: ImportContext())
        #expect(fb2.document.chapters.map(\.title) == ["Authors", "One"])
        let epubURL = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).epub")
        try EPUBWriter().write(original, cover: nil).write(to: epubURL)
        let epub = try await EPUBImporter().importBook(from: epubURL, context: ImportContext())
        #expect(epub.document.chapters.map(\.title) == ["Authors", "One"])
    }

    @Test func leadingUntitledChildSectionMergesIntoPart() async throws {
        let result = try await Self.importFB2("""
        <body><section><title><p>Part</p></title>
          <section><p>Intro.</p></section>
          <section><title><p>One</p></title><p>Body.</p></section>
        </section></body>
        """)
        let part = try #require(result.document.chapters.first)
        #expect(part.plainText == "Intro.")
        #expect(part.children.map(\.title) == ["One"])
    }

    @Test func inlineMarkupSubtitleAndEmptyLines() async throws {
        let result = try await Self.importFB2("""
        <body><section><title><p>T</p></title>
          <p>a <strong>b <emphasis>c</emphasis></strong>
             d <a l:href="#x">link</a></p>
          <empty-line/><subtitle>Sub</subtitle>
        </section></body>
        """)
        let blocks = try #require(result.document.chapters.first?.blocks)
        #expect(blocks == [
            .paragraph([InlineRun("a "), InlineRun("b ", bold: true), InlineRun("c", bold: true, italic: true), InlineRun(" d link")]),
            .heading(level: 3, runs: [InlineRun("Sub")]),
        ])
    }

    @Test func imagesGetDocumentOrderIdsAndTolerateWhitespaceInBase64() async throws {
        let png = FixtureFactory.pngImage(width: 4, height: 2)
        let other = FixtureFactory.pngImage(width: 2, height: 5)
        let spaced = png.data.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
            .replacing("\n", with: "\n   ")
        let result = try await Self.importFB2("""
        <body><section><title><p>T</p></title>
          <image l:href="#b.png"/><p>x</p><image l:href="#a.png"/><image l:href="#b.png"/><image l:href="#gone"/>
        </section></body>
        <binary id="a.png" content-type="image/png">\(other.data.base64EncodedString())</binary>
        <binary id="b.png" content-type="image/png">\(spaced)</binary>
        """)
        let images = result.document.allImages
        #expect(images.map(\.id) == ["img-1", "img-2", "img-1"])
        #expect(images.map(\.pixelWidth) == [4, 2, 4])
        #expect(result.warnings.contains(.imagesUnavailable(count: 1)))
    }

    @Test func coverGoesToSourceCoverOnly() async throws {
        let cover = FixtureFactory.pngImage(width: 7, height: 7)
        let result = try await Self.importFB2(
            """
            <body><section><title><p>T</p></title><p>x</p></section></body>
            <binary id="c.png" content-type="image/png">\(cover.data.base64EncodedString())</binary>
            """,
            titleInfoExtra: "<coverpage><image l:href=\"#c.png\"/></coverpage>"
        )
        #expect(result.sourceCover?.pixelWidth == 7)
        #expect(result.document.allImages.isEmpty)
    }

    // MARK: - Metadata fallbacks

    @Test func authorFallsBackToNickname() async throws {
        let result = try await Self.importFB2(
            "<body><section><p>x</p></section></body>",
            author: "<author><nickname>ghost</nickname></author>"
        )
        #expect(result.document.metadata.author == "ghost")
    }

    @Test func missingLanguageIsDetectedThenUndetermined() async throws {
        let russian = String(repeating: "Это длинный русский текст о том, как люди читают книги по вечерам. ", count: 12)
        let detected = try await Self.importFB2("<body><section><p>\(russian)</p></section></body>", lang: nil)
        #expect(detected.document.metadata.language == "ru")
        #expect(!detected.warnings.contains(.languageUndetermined))

        let unknown = try await Self.importFB2("<body><section><p>1 2 3</p></section></body>", lang: nil)
        #expect(unknown.document.metadata.language == "und")
        #expect(unknown.warnings.contains(.languageUndetermined))
    }

    @Test func sloppyMarkupAndEntitiesAreTolerated() async throws {
        let result = try await Self.importFB2("<body><section><title><p>AT&T &nbsp;&hellip;</p></title><p>Fish & chips</p></section></body>")
        #expect(result.document.chapters.first?.title == "AT&T \u{A0}\u{2026}")
        #expect(result.document.chapters.first?.plainText == "Fish & chips")
    }

    // MARK: - Errors

    @Test func truncatedDocumentKeepsContentAndWarns() async throws {
        let text = """
        <?xml version="1.0" encoding="UTF-8"?>
        <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0"><description><title-info>
        <book-title>Cut</book-title><lang>en</lang></title-info></description>
        <body><section><title><p>One</p></title><p>Kept.</p></section><section><title><p>Two</p></title><p>Lost <emphasis
        """
        let result = try await FB2Importer().importBook(from: Self.write(Data(text.utf8)), context: ImportContext())
        #expect(result.document.chapters.first?.plainText == "Kept.")
        #expect(result.warnings.contains(.contentPartiallyUnreadable(count: 1)))
    }

    @Test func nonFB2InputsThrow() async throws {
        await #expect(throws: ImportError.self) {
            try await FB2Importer().importBook(from: Self.write(Data("just text".utf8)), context: ImportContext())
        }
        await #expect(throws: ImportError.self) {
            try await FB2Importer().importBook(from: Self.write(Data("<html><body/></html>".utf8)), context: ImportContext())
        }
        await #expect(throws: ImportError.emptyDocument) {
            try await FB2Importer().importBook(
                from: Self.write(Data("<FictionBook><body><section><empty-line/></section></body></FictionBook>".utf8)),
                context: ImportContext()
            )
        }
    }

    // MARK: - Fixtures

    private struct OutlineNode: Equatable {
        var title: String?
        var text: String
        var children: [OutlineNode]
    }

    private static func outline(_ chapters: [Chapter]) -> [OutlineNode] {
        chapters.map {
            OutlineNode(title: $0.title, text: EPUBImporterTests.asWritten($0.plainText), children: outline($0.children))
        }
    }

    private static func write(_ data: Data) throws -> URL {
        let dir = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "book.fb2")
        try data.write(to: url)
        return url
    }

    /// Imports a hand-written FictionBook with the given `<body>` and `<binary>` markup.
    private static func importFB2(
        _ content: String, lang: String? = "en", author: String = "<author><first-name>A</first-name><last-name>B</last-name></author>",
        titleInfoExtra: String = ""
    ) async throws -> ImportResult {
        let langElement = lang.map { "<lang>\($0)</lang>" } ?? ""
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0" xmlns:l="http://www.w3.org/1999/xlink">
        <description><title-info>\(author)<book-title>Book</book-title>\(titleInfoExtra)\(langElement)</title-info></description>
        \(content)
        </FictionBook>
        """
        return try await FB2Importer().importBook(from: write(Data(xml.utf8)), context: ImportContext())
    }
}
