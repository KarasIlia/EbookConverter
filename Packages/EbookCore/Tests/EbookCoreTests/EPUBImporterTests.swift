import Foundation
import Testing
@testable import EbookCore

@Suite struct EPUBImporterTests {
    // MARK: - Round trip

    @Test func epubRoundTripKeepsStructure() async throws {
        let original = FixtureFactory.sampleDocument()
        let cover = FixtureFactory.pngImage(width: 3, height: 3, id: "cover")
        let url = try Self.write(EPUBWriter().write(original, cover: cover))

        let result = try await EPUBImporter().importBook(from: url, context: ImportContext())
        let imported = result.document

        #expect(imported.metadata == original.metadata)
        #expect(Self.outline(imported.chapters) == Self.outline(original.chapters))
        #expect(imported.allImages.count == original.allImages.count)
        #expect(imported.allImages.map(\.id) == ["img-1"])
        #expect(result.sourceCover != nil)
        #expect(result.warnings.isEmpty)
        #expect(zip(imported.leafChapters, original.leafChapters).allSatisfy {
            Self.stripInvalidXML($1.plainText) == $0.plainText
        })
        // Part's own blocks and inline styles survive.
        #expect(imported.chapters[0].plainText == "Part intro.")
        let first = imported.chapters[0].children[0]
        #expect(first.blocks.first == .paragraph([
            InlineRun("Plain "), InlineRun("bold", bold: true), InlineRun(" and "), InlineRun("italic", italic: true), InlineRun("."),
        ]))
    }

    @Test func importsWithoutCover() async throws {
        let url = try Self.write(EPUBWriter().write(FixtureFactory.sampleDocument(), cover: nil))
        let result = try await EPUBImporter().importBook(from: url, context: ImportContext())
        #expect(result.sourceCover == nil)
        #expect(result.document.chapters.count == 2)
    }

    // MARK: - Handcrafted packages

    @Test func ncxFragmentsMapToOneChapterAndUnlistedFilesAreAppended() async throws {
        let files: [String: String] = [
            "OEBPS/toc.ncx": Self.ncx("""
            <navPoint><navLabel><text>One</text></navLabel><content src="a.xhtml"/>
              <navPoint><navLabel><text>One-A</text></navLabel><content src="a.xhtml#sec"/></navPoint>
            </navPoint>
            <navPoint><navLabel><text>Two</text></navLabel><content src="b.xhtml#top"/></navPoint>
            """),
            "OEBPS/a.xhtml": Self.page("<h1>One</h1><p>Alpha.</p>"),
            "OEBPS/extra.xhtml": Self.page("<p>Unlisted continuation.</p>"),
            "OEBPS/b.xhtml": Self.page("<h2>Two</h2><p>Beta.</p>"),
        ]
        let url = try Self.epub(
            manifest: """
            <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            <item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>
            <item id="x" href="extra.xhtml" media-type="application/xhtml+xml"/>
            <item id="b" href="b.xhtml" media-type="application/xhtml+xml"/>
            """,
            spine: ["a", "x", "b"], files: files
        )
        let result = try await EPUBImporter().importBook(from: url, context: ImportContext())
        let chapters = result.document.chapters
        #expect(chapters.map(\.title) == ["One", "Two"])
        #expect(chapters[0].children.isEmpty)
        #expect(chapters[0].plainText == "Alpha.\nUnlisted continuation.")
        #expect(chapters[1].plainText == "Beta.")
        #expect(result.document.metadata.language == "en")
    }

    @Test func navHierarchyIsCappedAtTwoLevels() async throws {
        let nav = Self.page("""
        <nav epub:type="toc"><ol>
          <li><a href="a.xhtml">Part</a><ol>
            <li><a href="b.xhtml">Chapter</a><ol><li><a href="c.xhtml">Deep</a></li></ol></li>
          </ol></li>
        </ol></nav>
        """)
        let url = try Self.epub(
            manifest: """
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>
            <item id="b" href="b.xhtml" media-type="application/xhtml+xml"/>
            <item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>
            """,
            spine: ["nav", "a", "b", "c"],
            files: [
                "OEBPS/nav.xhtml": nav,
                "OEBPS/a.xhtml": Self.page("<h1>Part</h1><p>Intro.</p>"),
                "OEBPS/b.xhtml": Self.page("<h2>Chapter</h2><p>Body.</p>"),
                "OEBPS/c.xhtml": Self.page("<h2>Deep</h2><p>Deeper.</p>"),
            ]
        )
        let result = try await EPUBImporter().importBook(from: url, context: ImportContext())
        let part = try #require(result.document.chapters.first)
        #expect(result.document.chapters.count == 1)
        #expect(part.title == "Part")
        #expect(part.plainText == "Intro.")
        #expect(part.children.map(\.title) == ["Chapter", "Deep"])
        #expect(part.children.allSatisfy { $0.children.isEmpty })
    }

    @Test func coverOnlyPageIsSkippedAndCoverReturned() async throws {
        let cover = FixtureFactory.pngImage(width: 5, height: 5, id: "c")
        let url = try Self.epub(
            manifest: """
            <item id="cover-img" href="images/cover.png" media-type="image/png" properties="cover-image"/>
            <item id="cover" href="cover.xhtml" media-type="application/xhtml+xml"/>
            <item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>
            """,
            spine: ["cover", "a"],
            files: [
                "OEBPS/cover.xhtml": Self.page("<div><img src=\"images/cover.png\" alt=\"\"/></div>"),
                "OEBPS/a.xhtml": Self.page("<h1>Only</h1><p>Text.</p>"),
            ],
            binaries: ["OEBPS/images/cover.png": cover.data]
        )
        let result = try await EPUBImporter().importBook(from: url, context: ImportContext())
        #expect(result.sourceCover?.pixelWidth == 5)
        #expect(result.document.chapters.count == 1)
        #expect(result.document.allImages.isEmpty)
    }

    @Test func legacyCoverMetaAndImagesInDocumentOrder() async throws {
        let cover = FixtureFactory.pngImage(width: 6, height: 6)
        let other = FixtureFactory.pngImage(width: 2, height: 3)
        let url = try Self.epub(
            metadataExtra: "<meta name=\"cover\" content=\"cv\"/>",
            manifest: """
            <item id="cv" href="img/cover.png" media-type="image/png"/>
            <item id="p1" href="img/one.png" media-type="image/png"/>
            <item id="a" href="text/a.xhtml" media-type="application/xhtml+xml"/>
            """,
            spine: ["a"],
            files: ["OEBPS/text/a.xhtml": Self.page("<h1>T</h1><p>x</p><img src=\"../img/one.png\"/><p>y</p><img src=\"../img/one.png\"/><img src=\"../img/missing.png\"/>")],
            binaries: ["OEBPS/img/cover.png": cover.data, "OEBPS/img/one.png": other.data]
        )
        let result = try await EPUBImporter().importBook(from: url, context: ImportContext())
        #expect(result.sourceCover?.pixelWidth == 6)
        #expect(result.document.allImages.map(\.id) == ["img-1", "img-1"])
        #expect(result.document.allImages.first?.pixelHeight == 3)
        #expect(result.warnings.contains(.imagesUnavailable(count: 1)))
    }

    @Test func missingLanguageFallsBackToDetectionThenUndetermined() async throws {
        let russian = String(repeating: "Это длинный русский текст о том, как люди читают книги по вечерам. ", count: 12)
        let url = try Self.epub(
            language: nil, manifest: "<item id=\"a\" href=\"a.xhtml\" media-type=\"application/xhtml+xml\"/>",
            spine: ["a"], files: ["OEBPS/a.xhtml": Self.page("<p>\(russian)</p>")]
        )
        let detected = try await EPUBImporter().importBook(from: url, context: ImportContext())
        #expect(detected.document.metadata.language == "ru")

        let blank = try Self.epub(
            language: "  ", manifest: "<item id=\"a\" href=\"a.xhtml\" media-type=\"application/xhtml+xml\"/>",
            spine: ["a"], files: ["OEBPS/a.xhtml": Self.page("<p>42</p>")]
        )
        let undetermined = try await EPUBImporter().importBook(from: blank, context: ImportContext())
        #expect(undetermined.document.metadata.language == "und")
        #expect(undetermined.warnings.contains(.languageUndetermined))
    }

    @Test func hrefsCannotEscapeTheArchive() async throws {
        let url = try Self.epub(
            manifest: """
            <item id="evil" href="../../secret.xhtml" media-type="application/xhtml+xml"/>
            <item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>
            """,
            spine: ["evil", "a"],
            files: [
                "secret.xhtml": Self.page("<p>SECRET</p>"),
                "OEBPS/a.xhtml": Self.page("<h1>A</h1><p>Fine.</p><img src=\"../../secret.png\"/>"),
            ],
            binaries: ["secret.png": FixtureFactory.pngImage(width: 2, height: 2).data]
        )
        let result = try await EPUBImporter().importBook(from: url, context: ImportContext())
        #expect(!result.document.chapters.map(\.plainText).joined().contains("SECRET"))
        #expect(result.document.allImages.isEmpty)
    }

    @Test func dotDotInsideArchiveIsNormalized() async throws {
        let url = try Self.epub(
            manifest: "<item id=\"a\" href=\"text/../chapters/./a%20b.xhtml\" media-type=\"application/xhtml+xml\"/>",
            spine: ["a"], files: ["OEBPS/chapters/a b.xhtml": Self.page("<p>Found.</p>")]
        )
        let result = try await EPUBImporter().importBook(from: url, context: ImportContext())
        #expect(result.document.chapters.first?.plainText == "Found.")
    }

    @Test func unreadableInputsThrow() async throws {
        let notZip = try Self.write(Data("plain text".utf8))
        await #expect(throws: ImportError.self) { try await EPUBImporter().importBook(from: notZip, context: ImportContext()) }

        let noContainer = try Self.write(ZipWriter.archive([ZipEntry(path: "a.txt", data: Data("x".utf8))]))
        await #expect(throws: ImportError.self) { try await EPUBImporter().importBook(from: noContainer, context: ImportContext()) }

        let empty = try Self.epub(
            manifest: "<item id=\"a\" href=\"a.xhtml\" media-type=\"application/xhtml+xml\"/>",
            spine: ["a"], files: ["OEBPS/a.xhtml": Self.page("")]
        )
        await #expect(throws: ImportError.emptyDocument) { try await EPUBImporter().importBook(from: empty, context: ImportContext()) }
    }

    @Test func corruptSpineFileIsReportedAndOthersSurvive() async throws {
        let url = try Self.epub(
            manifest: """
            <item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>
            <item id="b" href="b.xhtml" media-type="application/xhtml+xml"/>
            <item id="c" href="c.xhtml" media-type="application/xhtml+xml"/>
            """,
            spine: ["a", "b", "c"],
            files: [
                "OEBPS/a.xhtml": Self.page("<h1>A</h1><p>Alpha.</p>"),
                "OEBPS/b.xhtml": Self.page("<h1>B</h1><p>Beta.</p>"),
                "OEBPS/c.xhtml": Self.page("<h1>C</h1><p>Gamma.</p>"),
            ]
        )
        var bytes = try Data(contentsOf: url)
        let name = try #require(bytes.range(of: Data("OEBPS/b.xhtml".utf8)))
        bytes[name.upperBound + 3] ^= 0xFF // inside the entry's payload
        try bytes.write(to: url)

        let result = try await EPUBImporter().importBook(from: url, context: ImportContext())
        #expect(result.document.chapters.map(\.title) == ["A", "C"])
        #expect(result.warnings.contains(.contentPartiallyUnreadable(count: 1)))
    }

    @Test func sloppyMarkupKeepsWholeChapterWithoutWarning() async throws {
        let url = try Self.epub(
            manifest: "<item id=\"a\" href=\"a.xhtml\" media-type=\"text/html\"/>",
            spine: ["a"],
            files: ["OEBPS/a.xhtml": "<html><body><h1>T</h1><p>AT&T line<br>two</p><p>after</p></body></html>"]
        )
        let result = try await EPUBImporter().importBook(from: url, context: ImportContext())
        #expect(result.document.chapters.first?.plainText == "AT&T line two\nafter")
        #expect(!result.warnings.contains { if case .contentPartiallyUnreadable = $0 { true } else { false } })
    }

    @Test func truncatedMarkupIsReported() async throws {
        let url = try Self.epub(
            manifest: "<item id=\"a\" href=\"a.xhtml\" media-type=\"application/xhtml+xml\"/>",
            spine: ["a"],
            files: ["OEBPS/a.xhtml": "<html><body><h1>T</h1><p>Kept.</p><p>Broken <b></p></body></html>"]
        )
        let result = try await EPUBImporter().importBook(from: url, context: ImportContext())
        #expect(result.document.chapters.first?.plainText == "Kept.\nBroken")
        #expect(result.warnings.contains(.contentPartiallyUnreadable(count: 1)))
    }

    @Test func tocLabelsKeepInlineMarkupInOrder() async throws {
        let nav = Self.page("""
        <nav epub:type="toc"><ol>
          <li><a href="a.xhtml">Chapter <em>One</em>: Start</a></li>
          <li><a href="b.xhtml">Chap<i>ter</i> Two</a></li>
        </ol></nav>
        """)
        let url = try Self.epub(
            manifest: """
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>
            <item id="b" href="b.xhtml" media-type="application/xhtml+xml"/>
            """,
            spine: ["a", "b"],
            files: [
                "OEBPS/nav.xhtml": nav,
                "OEBPS/a.xhtml": Self.page("<p>One.</p>"),
                "OEBPS/b.xhtml": Self.page("<p>Two.</p>"),
            ]
        )
        let result = try await EPUBImporter().importBook(from: url, context: ImportContext())
        #expect(result.document.chapters.map(\.title) == ["Chapter One: Start", "Chapter Two"])
    }

    @Test func archiveExpandingPastTheBudgetIsRefused() async throws {
        let url = try Self.write(EPUBWriter().write(FixtureFactory.sampleDocument(), cover: nil))
        await #expect(throws: ImportError.self) {
            try await EPUBImporter(totalBudget: 200).importBook(from: url, context: ImportContext())
        }
    }

    @Test func firstDeclaredCoverImageWins() async throws {
        let first = FixtureFactory.pngImage(width: 7, height: 7)
        let second = FixtureFactory.pngImage(width: 9, height: 9)
        let url = try Self.epub(
            manifest: """
            <item id="c1" href="one.png" media-type="image/png" properties="cover-image"/>
            <item id="c2" href="two.png" media-type="image/png" properties="cover-image"/>
            <item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>
            """,
            spine: ["a"], files: ["OEBPS/a.xhtml": Self.page("<p>Text.</p>")],
            binaries: ["OEBPS/one.png": first.data, "OEBPS/two.png": second.data]
        )
        let result = try await EPUBImporter().importBook(from: url, context: ImportContext())
        #expect(result.sourceCover?.pixelWidth == 7)
    }

    @Test func imageOnlyFirstPageBecomesCoverWhenNoneDeclared() async throws {
        let picture = FixtureFactory.pngImage(width: 8, height: 8)
        let url = try Self.epub(
            manifest: """
            <item id="p" href="p.xhtml" media-type="application/xhtml+xml"/>
            <item id="a" href="a.xhtml" media-type="application/xhtml+xml"/>
            """,
            spine: ["p", "a"],
            files: [
                "OEBPS/p.xhtml": Self.page("<div><img src=\"pic.png\"/></div>"),
                "OEBPS/a.xhtml": Self.page("<h1>T</h1><p>Text.</p>"),
            ],
            binaries: ["OEBPS/pic.png": picture.data]
        )
        let result = try await EPUBImporter().importBook(from: url, context: ImportContext())
        #expect(result.sourceCover?.pixelWidth == 8)
        #expect(result.document.allImages.isEmpty)
    }

    @Test func utf16PackageAndContentDocumentsImport() async throws {
        let container = """
        <?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
        """
        let opf = """
        <?xml version="1.0" encoding="UTF-16"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Ц &amp; Wait\u{2026}</dc:title><dc:language>en</dc:language></metadata>
        <manifest><item id="a" href="a.xhtml" media-type="application/xhtml+xml"/></manifest>
        <spine><itemref idref="a"/></spine></package>
        """
        let page = Self.page("<h1>T</h1><p>Wait\u{2026} \u{426} &amp; AT&T<br>end</p>")
            .replacing("UTF-8", with: "UTF-16")
        let zip = try ZipWriter.archive([
            ZipEntry(path: "META-INF/container.xml", data: Data(container.utf8)),
            ZipEntry(path: "OEBPS/content.opf", data: try #require(opf.data(using: .utf16LittleEndian)).withBOM(.utf16LittleEndian)),
            ZipEntry(path: "OEBPS/a.xhtml", data: try #require(page.data(using: .utf16BigEndian)).withBOM(.utf16BigEndian)),
        ])
        let result = try await EPUBImporter().importBook(from: Self.write(zip), context: ImportContext())
        #expect(result.document.metadata.title == "Ц & Wait\u{2026}")
        #expect(result.document.chapters.first?.plainText == "Wait\u{2026} \u{426} & AT&T end")
        #expect(!result.warnings.contains { if case .contentPartiallyUnreadable = $0 { true } else { false } })
    }

    // MARK: - Fixtures

    static func stripInvalidXML(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { ![0x0B, 0x0C].contains($0.value) }))
    }

    private struct OutlineNode: Equatable {
        var title: String?
        var text: String
        var children: [OutlineNode]
    }

    private static func outline(_ chapters: [Chapter]) -> [OutlineNode] {
        chapters.map { OutlineNode(title: $0.title, text: stripInvalidXML($0.plainText), children: outline($0.children)) }
    }

    static func write(_ data: Data) throws -> URL {
        let dir = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "book.epub")
        try data.write(to: url)
        return url
    }

    static func page(_ body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>t</title></head><body>\(body)</body></html>
        """
    }

    static func ncx(_ points: String) -> String {
        "<?xml version=\"1.0\"?><ncx xmlns=\"http://www.daisy.org/z3986/2005/ncx/\" version=\"2005-1\"><navMap>\(points)</navMap></ncx>"
    }

    /// A package with `OEBPS/content.opf`; `files` and `binaries` are keyed by archive path.
    static func epub(
        language: String? = "en", metadataExtra: String = "", manifest: String, spine: [String],
        files: [String: String], binaries: [String: Data] = [:]
    ) throws -> URL {
        let languageElement = language.map { "<dc:language>\($0)</dc:language>" } ?? ""
        let opf = """
        <?xml version="1.0"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Hand Made</dc:title><dc:creator>Someone</dc:creator>\(languageElement)\(metadataExtra)
          </metadata>
          <manifest>\(manifest)</manifest>
          <spine toc="ncx">\(spine.map { "<itemref idref=\"\($0)\"/>" }.joined())</spine>
        </package>
        """
        let container = """
        <?xml version="1.0"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
        """
        var entries = [
            ZipEntry(path: "mimetype", data: Data("application/epub+zip".utf8), method: .stored),
            ZipEntry(path: "META-INF/container.xml", data: Data(container.utf8)),
            ZipEntry(path: "OEBPS/content.opf", data: Data(opf.utf8)),
        ]
        entries += files.sorted { $0.key < $1.key }.map { ZipEntry(path: $0.key, data: Data($0.value.utf8)) }
        entries += binaries.sorted { $0.key < $1.key }.map { ZipEntry(path: $0.key, data: $0.value, method: .stored) }
        return try write(ZipWriter.archive(entries))
    }
}

private extension Data {
    func withBOM(_ encoding: String.Encoding) -> Data {
        Data(encoding == .utf16LittleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF]) + self
    }
}
