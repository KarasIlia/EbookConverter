import AppKit
import Testing
@testable import EbookCore

@Suite struct AttributedTextImporterTests {
    private static let body = TextEncodingTests.russian

    private static func font(_ size: Double, bold: Bool = false, italic: Bool = false) -> NSFont {
        var font = NSFont(name: "Times New Roman", size: size) ?? NSFont.systemFont(ofSize: size)
        if bold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }

    /// Heading/body pairs: headings 18 pt bold, body 12 pt.
    private static func book(_ headings: [String]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for heading in headings {
            result.append(NSAttributedString(string: heading + "\n", attributes: [.font: font(18, bold: true)]))
            result.append(NSAttributedString(string: body + "\n", attributes: [.font: font(12)]))
        }
        return result
    }

    private func folder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func importBook(_ url: URL, context: ImportContext = ImportContext()) async throws -> ImportResult {
        try await AttributedTextImporter().importBook(from: url, context: context)
    }

    /// Escapes `text` as RTF `\'hh` bytes in `encoding`.
    private static func rtfHex(_ text: String, encoding: String.Encoding) -> String {
        (text.data(using: encoding) ?? Data()).map { byte in
            byte < 0x80 ? String(UnicodeScalar(byte)) : "\\'" + String(byte, radix: 16)
        }.joined()
    }

    @Test func docxHeadingsByFontSize() async throws {
        let url = try FixtureFactory.wordFile(Self.book(["Глава 1", "Глава 2"]), type: .officeOpenXML)
        let result = try await importBook(url)
        #expect(result.document.chapters.map(\.title) == ["Глава 1", "Глава 2"])
        #expect(result.document.metadata.language == "ru")
    }

    @Test func docxHeadingsWithoutPatternBySize() async throws {
        let url = try FixtureFactory.wordFile(Self.book(["Начало пути", "Конец"]), type: .officeOpenXML)
        let result = try await importBook(url)
        #expect(result.document.chapters.map(\.title) == ["Начало пути", "Конец"])
    }

    @Test func docFormatSupported() async throws {
        let url = try FixtureFactory.wordFile(Self.book(["Глава 1", "Глава 2"]), type: .docFormat)
        let result = try await importBook(url)
        #expect(result.document.chapters.map(\.title) == ["Глава 1", "Глава 2"])
    }

    @Test func rtfWithDocExtensionDetected() async throws {
        let rtfURL = try FixtureFactory.wordFile(Self.book(["Глава 1", "Глава 2"]), type: .rtf)
        let url = try folder().appending(path: "x.doc")
        try Data(contentsOf: rtfURL).write(to: url)
        let result = try await importBook(url)
        #expect(result.document.chapters.map(\.title) == ["Глава 1", "Глава 2"])
        #expect(result.document.metadata.title == "x")
    }

    @Test func boldItalicRunsPreserved() async throws {
        let text = NSMutableAttributedString(string: "plain ", attributes: [.font: Self.font(12)])
        text.append(NSAttributedString(string: "bold", attributes: [.font: Self.font(12, bold: true)]))
        text.append(NSAttributedString(string: " and ", attributes: [.font: Self.font(12)]))
        text.append(NSAttributedString(string: "italic", attributes: [.font: Self.font(12, italic: true)]))
        let url = try FixtureFactory.wordFile(text, type: .officeOpenXML)
        let result = try await importBook(url)
        let runs = result.document.chapters.flatMap(\.blocks).compactMap { block -> [InlineRun]? in
            if case .paragraph(let runs) = block { runs } else { nil }
        }.flatMap(\.self)
        #expect(runs.contains { $0.text == "bold" && $0.isBold && !$0.isItalic })
        #expect(runs.contains { $0.text == "italic" && $0.isItalic && !$0.isBold })
        #expect(runs.contains { $0.text.hasPrefix("plain") && !$0.isBold && !$0.isItalic })
    }

    @Test func flattenerUsesHeaderLevelAndDominantSize() {
        let style = NSMutableParagraphStyle()
        style.headerLevel = 2
        let text = NSMutableAttributedString(string: "Intro:\n", attributes: [.font: Self.font(12), .paragraphStyle: style])
        text.append(NSAttributedString(string: "big", attributes: [.font: Self.font(20)]))
        text.append(NSAttributedString(string: " small text\u{FFFC}", attributes: [.font: Self.font(10)]))
        let items = AttributedStringFlattener.items(from: text)
        let paragraphs = items.compactMap { item -> StyledParagraph? in
            if case .paragraph(let paragraph) = item { paragraph } else { nil }
        }
        #expect(paragraphs.count == 2)
        #expect(paragraphs.first?.headingLevelHint == 2)
        #expect(paragraphs.last?.headingLevelHint == nil)
        #expect(paragraphs.last?.fontSize == 10)
        #expect(paragraphs.last?.text == "big small text")
    }

    @Test func rtfMetadataDecodedFromDeclaredCodepage() async throws {
        // Same shape as the user's sample sample: `\ansicpg` without a number, CP1251 via \fcharset204,
        // raw (unescaped) CP1251 bytes in \info.
        let title = "Хочу в программисты! Основы разработки для начинающих"
        let author = "Иван Петров"
        var data = Data(#"{\rtf1\ansi\ansicpg\deff0\deflang1049{\fonttbl{\f0\fswiss\fprq2\fcharset204{\*\fname Arial CYR;}Arial;}}{\info"#.utf8)
        data.append(Data("\n{\\title ".utf8))
        data.append(try #require(title.data(using: .windowsCP1251)))
        data.append(Data("}\n{\\author ".utf8))
        data.append(try #require(author.data(using: .windowsCP1251)))
        data.append(Data("}\n}".utf8))
        data.append(Data("{\\f0\\fs24 \(Self.rtfHex(Self.body, encoding: .windowsCP1251))\\par}}".utf8))
        let url = try folder().appending(path: "sample.doc")
        try data.write(to: url)

        let result = try await importBook(url)
        #expect(result.document.metadata.title == title)
        #expect(result.document.metadata.author == author)
        #expect(result.document.metadata.language == "ru")
    }

    @Test func titleFallsBackToFilename() async throws {
        let dir = try folder()
        let url = dir.appending(path: "My_Book.docx")
        try Data(contentsOf: FixtureFactory.wordFile(Self.book(["Глава 1"]), type: .officeOpenXML)).write(to: url)
        let result = try await importBook(url)
        #expect(result.document.metadata.title == "My Book")
        #expect(result.document.metadata.author == "")
    }

    @Test(.disabled("NSAttributedString drops DOCX images on this OS")) func docxImageAttachmentKept() async throws {
        let attachment = NSTextAttachment()
        attachment.fileWrapper = FileWrapper(regularFileWithContents: FixtureFactory.pngImage(width: 20, height: 10).data)
        attachment.fileWrapper?.preferredFilename = "pic.png"
        let text = NSMutableAttributedString(attributedString: Self.book(["Глава 1"]))
        text.append(NSAttributedString(attachment: attachment))
        let url = try FixtureFactory.wordFile(text, type: .officeOpenXML)
        let result = try await importBook(url)
        #expect(result.document.allImages.count == 1)
    }

    @Test func docImagePlaceholderWarnsUnavailable() async throws {
        // NSAttributedString writes a U+FFFC but no image data for attachments in .doc output.
        let attachment = NSTextAttachment()
        attachment.fileWrapper = FileWrapper(regularFileWithContents: FixtureFactory.pngImage(width: 20, height: 10).data)
        let text = NSMutableAttributedString(attributedString: Self.book(["Глава 1"]))
        text.append(NSAttributedString(attachment: attachment))
        let url = try FixtureFactory.wordFile(text, type: .docFormat)
        let result = try await importBook(url)
        #expect(result.document.allImages.isEmpty)
        #expect(result.warnings.contains(.imagesUnavailable(count: 1)))
        #expect(!result.document.leafChapters.contains { $0.plainText.contains("\u{FFFC}") })
    }

    @Test func rtfdAttachmentBecomesImage() async throws {
        let attachment = NSTextAttachment()
        attachment.fileWrapper = FileWrapper(regularFileWithContents: FixtureFactory.pngImage(width: 20, height: 10).data)
        let text = NSMutableAttributedString(attributedString: Self.book(["Глава 1"]))
        text.append(NSAttributedString(attachment: attachment))
        text.append(NSAttributedString(attachment: attachment))
        let items = AttributedStringFlattener.items(from: text)
        let images = items.compactMap { item -> ImageAsset? in
            if case .image(let asset) = item { asset } else { nil }
        }
        #expect(images.map(\.pixelWidth) == [20, 20])
    }

    @Test func htmlImagesResolvedInOrder() async throws {
        let dir = try folder()
        try FixtureFactory.pngImage(width: 20, height: 10).data.write(to: dir.appending(path: "a.png"))
        try FixtureFactory.pngImage(width: 10, height: 30).data.write(to: dir.appending(path: "b c.png"))
        let html = """
        <html><head><meta charset="utf-8"></head><body>
        <h2>Глава 1</h2><p>\(Self.body)</p>
        <img src="a.png"><img src='https://example.com/x.png'><img src="//cdn.example.com/y.png">
        <h2>Глава 2</h2><p>\(Self.body)</p>
        <img alt="b" src="b%20c.png"><img src="nope.png">
        </body></html>
        """
        let url = dir.appending(path: "book.html")
        try Data(html.utf8).write(to: url)
        let result = try await importBook(url)
        #expect(result.document.chapters.map(\.title) == ["Глава 1", "Глава 2"])
        #expect(result.document.allImages.map(\.id) == ["img-1", "img-2"])
        #expect(result.document.allImages.map(\.pixelHeight) == [10, 30])
        #expect(result.warnings.contains(.remoteImagesSkipped(count: 2)))
        #expect(result.warnings.contains(.imagesNeedFolderAccess(folder: url.deletingLastPathComponent())))
    }

    @Test func htmlMissingImageWithFolderIsUnavailable() async throws {
        let dir = try folder()
        let html = "<html><body><h2>A</h2><p>\(Self.body)</p><img src=\"nope.png\"></body></html>"
        let url = dir.appending(path: "book.htm")
        try Data(html.utf8).write(to: url)
        let result = try await importBook(url, context: ImportContext(accessibleFolder: dir))
        #expect(result.warnings.contains(.imagesUnavailable(count: 1)))
        #expect(result.document.allImages.isEmpty)
    }

    @Test func htmlDeclaredLegacyCharsetDecoded() async throws {
        var data = Data(#"<html><head><meta http-equiv="Content-Type" content="text/html; charset=windows-1251"></head><body><h2>"#.utf8)
        data.append(try #require("Глава 1".data(using: .windowsCP1251)))
        data.append(Data("</h2><p>".utf8))
        data.append(try #require(Self.body.data(using: .windowsCP1251)))
        data.append(Data("</p></body></html>".utf8))
        let url = try folder().appending(path: "legacy.html")
        try data.write(to: url)
        let result = try await importBook(url)
        #expect(result.document.chapters.map(\.title) == ["Глава 1"])
        #expect(result.document.metadata.language == "ru")
    }

    @Test func languageUndeterminedWarns() async throws {
        let url = try FixtureFactory.wordFile(NSAttributedString(string: "12 34", attributes: [.font: Self.font(12)]), type: .rtf)
        let result = try await importBook(url)
        #expect(result.document.metadata.language == "und")
        #expect(result.warnings.contains(.languageUndetermined))
        #expect(result.warnings.contains(.noChaptersFound))
    }

    @Test func emptyDocumentThrows() async throws {
        let url = try FixtureFactory.wordFile(NSAttributedString(string: " \n\n"), type: .rtf)
        await #expect(throws: ImportError.emptyDocument) {
            _ = try await importBook(url)
        }
    }

    // MARK: Fix round 1

    @Test func htmlTitleTakenFromTitleElement() async throws {
        let html = "<html><head><title>\n Тест &amp; книга &#8212; один </title></head><body><h2>A</h2><p>\(Self.body)</p></body></html>"
        let url = try folder().appending(path: "book.html")
        try Data(html.utf8).write(to: url)
        let result = try await importBook(url)
        #expect(result.document.metadata.title == "Тест & книга — один")
    }

    @Test func htmlImagesInCommentsScriptsAndTemplatesIgnored() async throws {
        let dir = try folder()
        try FixtureFactory.pngImage(width: 20, height: 10).data.write(to: dir.appending(path: "a.png"))
        try FixtureFactory.pngImage(width: 10, height: 30).data.write(to: dir.appending(path: "b.png"))
        let html = """
        <html><body><h2>A</h2><p>\(Self.body)</p>
        <!-- <img src="old.png"> -->
        <script>var s = '<img src="x.png">';</script>
        <noscript><img src="y.png"></noscript>
        <template><img src="z.png"></template>
        <img src="a.png"><p>text</p><img src="b.png">
        </body></html>
        """
        let url = dir.appending(path: "book.html")
        try Data(html.utf8).write(to: url)
        let result = try await importBook(url, context: ImportContext(accessibleFolder: dir))
        #expect(result.document.allImages.map(\.pixelHeight) == [10, 30])
        #expect(!result.warnings.contains { if case .imagesUnavailable = $0 { true } else { false } })
    }

    @Test func htmlSubresourcesNeutralized() {
        let html = """
        <html><head><link rel="stylesheet" href="http://e.example/s.css"><link rel=icon href=//e.example/i.png>
        <style>@import url("http://e.example/x.css"); body { background: url(http://e.example/c.png) }</style></head>
        <body><img src="a.png" srcset="http://e.example/a2.png 2x, a3.png 3x">
        <div style="background-image:url('http://e.example/b.png')">x</div>
        <iframe src="http://e.example/f"></iframe><video poster="http://e.example/p.png"></video>
        </body></html>
        """
        let (output, references) = HTMLSubresourceNeutralizer.neutralize(html)
        #expect(references == ["a.png"])
        #expect(!output.contains("e.example"))
        #expect(!output.contains("a3.png"))
    }
}
