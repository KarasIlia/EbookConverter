import Testing
import PDFKit
@testable import EbookCore

struct PDFImporterTests {
    /// Wrapped body text, one distinct passage per page (identical lines on every page would be running headers).
    private static let passages = [
        [
            "It was a bright cold day in April, and the clocks",
            "were striking thirteen. Winston Smith, his chin",
            "nuzzled into his breast in an effort to escape the",
            "vile wind, slipped quickly through the glass doors.",
        ],
        [
            "The hallway smelt of boiled cabbage and old rag",
            "mats. At one end of it a coloured poster, too large",
            "for indoor display, had been tacked to the wall by",
            "someone who had left long before Winston Smith came.",
        ],
        [
            "Outside, even through the shut window-pane, the",
            "world looked cold. Down in the street little eddies",
            "of wind were whirling dust and torn paper into spirals,",
            "and Winston Smith could see nobody walking there.",
        ],
    ]

    private static func bodyBoxes(_ lines: [String]) -> [FixtureTextBox] {
        lines.enumerated().map { index, text in
            FixtureTextBox(text, rect: CGRect(x: 72, y: 680 - Double(index) * 15, width: 450, height: 14))
        }
    }

    /// One page per chapter: a 20 pt heading followed by 12 pt body lines.
    private static func chapterPages(_ headings: [String]) -> [[FixtureTextBox]] {
        headings.enumerated().map { index, heading in
            [FixtureTextBox(heading, rect: CGRect(x: 72, y: 720, width: 400, height: 24), fontSize: 20)]
                + bodyBoxes(passages[index % passages.count])
        }
    }

    private func importBook(_ url: URL) async throws -> ImportResult {
        try await PDFImporter().importBook(from: url, context: ImportContext())
    }

    @Test func importsChaptersBySize() async throws {
        let url = try FixtureFactory.pdf(pages: Self.chapterPages(["The Beginning", "The Middle", "The End"]))
        let result = try await importBook(url)
        let chapters = result.document.chapters
        #expect(chapters.map(\.title) == ["The Beginning", "The Middle", "The End"])
        #expect(chapters.first?.blocks == [.paragraph([InlineRun(Self.passages[0].joined(separator: " "))])])
        #expect(result.document.metadata.language == "en")
        #expect(result.document.metadata.title == "fixture")
        #expect(result.warnings.isEmpty)
    }

    @Test func numberedChapterHeadingsMidPageSurvive() async throws {
        let url = try FixtureFactory.pdf(pages: Self.chapterPages(["Chapter 1", "Chapter 2", "Chapter 3"]).map { page in
            // Move the heading to mid-page, away from the header zone.
            [FixtureTextBox(page[0].text, rect: CGRect(x: 72, y: 500, width: 400, height: 24), fontSize: 20)]
                + page.dropFirst().map { FixtureTextBox($0.text, rect: $0.rect.offsetBy(dx: 0, dy: -240)) }
        })
        let chapters = try await importBook(url).document.chapters
        #expect(chapters.map(\.title) == ["Chapter 1", "Chapter 2", "Chapter 3"])
    }

    @Test func usesOutlineWhenPresent() async throws {
        let source = try FixtureFactory.pdf(pages: Self.chapterPages(["Heading A", "Heading B"]))
        let document = try #require(PDFDocument(url: source))
        let root = PDFOutline()
        for (index, label) in ["Outline One", "Outline Two"].enumerated() {
            let entry = PDFOutline()
            entry.label = label
            let page = try #require(document.page(at: index))
            entry.destination = PDFDestination(page: page, at: CGPoint(x: 72, y: 760))
            root.insertChild(entry, at: index)
        }
        document.outlineRoot = root
        document.documentAttributes = [PDFDocumentAttribute.titleAttribute: "  Outlined Book ", PDFDocumentAttribute.authorAttribute: "Jane Doe"]
        let url = source.deletingLastPathComponent().appending(path: "outlined_book.pdf")
        #expect(document.write(to: url))

        let result = try await importBook(url)
        let chapters = result.document.chapters
        #expect(chapters.map(\.title) == ["Outline One", "Outline Two"])
        #expect(chapters.allSatisfy { $0.plainText.contains("Winston Smith") })
        #expect(chapters[1].plainText.hasPrefix("Heading B"))
        #expect(result.document.metadata.title == "Outlined Book")
        #expect(result.document.metadata.author == "Jane Doe")
    }

    @Test func outlineNestsPartsAndFlattensDeeperLevels() async throws {
        let source = try FixtureFactory.pdf(pages: Self.chapterPages(["Heading A", "Heading B", "Heading C"]))
        let document = try #require(PDFDocument(url: source))
        func entry(_ label: String, page index: Int) throws -> PDFOutline {
            let entry = PDFOutline()
            entry.label = label
            entry.destination = PDFDestination(page: try #require(document.page(at: index)), at: CGPoint(x: 72, y: 760))
            return entry
        }
        let root = PDFOutline()
        let part = try entry("Part", page: 0)
        let chapter = try entry("Chapter", page: 0)
        chapter.insertChild(try entry("Section", page: 1), at: 0)
        part.insertChild(chapter, at: 0)
        root.insertChild(part, at: 0)
        root.insertChild(try entry("Appendix", page: 2), at: 1)
        document.outlineRoot = root
        let url = source.deletingLastPathComponent().appending(path: "nested.pdf")
        #expect(document.write(to: url))

        let chapters = try await importBook(url).document.chapters
        #expect(chapters.map(\.title) == ["Part", "Appendix"])
        #expect(chapters.first?.children.map(\.title) == ["Chapter", "Section"])
        #expect(chapters.first?.children.last?.plainText.hasPrefix("Heading B") == true)
    }

    @Test func noHeadingsWarns() async throws {
        let url = try FixtureFactory.pdf(pages: [Self.bodyBoxes(Self.passages[0])])
        let result = try await importBook(url)
        #expect(result.warnings.contains(.noChaptersFound))
        #expect(result.document.chapters.count == 1)
    }

    @Test func imageOnlyPdfThrowsNoTextLayer() async throws {
        let image = FixtureImageBox(page: 0, rect: CGRect(x: 50, y: 50, width: 400, height: 600), image: FixtureFactory.pngImage(width: 40, height: 60))
        let url = try FixtureFactory.pdf(pages: [[], []], images: [image])
        await #expect(throws: ImportError.pdfHasNoTextLayer) { try await importBook(url) }
    }

    @Test func nonPdfThrowsUnreadable() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
        try Data("not a pdf".utf8).write(to: url)
        await #expect {
            try await importBook(url)
        } throws: { error in
            if case ImportError.unreadable = error { true } else { false }
        }
    }

    @Test func lockedPdfThrows() async throws {
        let source = try FixtureFactory.pdf(pages: Self.chapterPages(["Secret"]))
        let document = try #require(PDFDocument(url: source))
        let url = source.deletingLastPathComponent().appending(path: "locked.pdf")
        #expect(document.write(to: url, withOptions: [
            .userPasswordOption: "user", .ownerPasswordOption: "owner",
        ]))
        await #expect(throws: ImportError.pdfLocked) { try await importBook(url) }
    }

    @Test func oneEmFirstLineIndentsSplitParagraphsInRealPDF() async throws {
        // Justified-looking lines: each paragraph's last line runs almost to the margin, so only the 1 em indent marks it.
        let lines: [(String, Double)] = [
            ("The morning was cold and the road was empty when the old", 12),
            ("man finally left the house and walked slowly to the river bank,", 0),
            ("thinking about the letter he had received the day before it.", 0),
            ("By noon he had reached the old bridge over the dark water and", 12),
            ("stood there for a long time watching the current run past him", 0),
            ("until the cold grey afternoon light began to fade over the hills.", 0),
        ]
        let boxes = lines.enumerated().map { index, entry in
            FixtureTextBox(entry.0, rect: CGRect(x: 72 + entry.1, y: 700 - Double(index) * 14.4, width: 460, height: 14), fontSize: 12)
        }
        let url = try FixtureFactory.pdf(pages: [boxes])
        let result = try await PDFImporter().importBook(from: url, context: ImportContext())
        let paragraphs = result.document.leafChapters.flatMap(\.blocks).compactMap { block -> String? in
            if case .paragraph(let runs) = block { return runs.map(\.text).joined() } else { return nil }
        }
        #expect(paragraphs.count == 2)
        #expect(paragraphs.last?.hasPrefix("By noon") == true)
    }
}
