import Foundation
import Testing
@testable import EbookCore

struct FB2WriterTests {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func xml(_ document: BookDocument, cover: ImageAsset? = nil) throws -> XMLDocument {
        let data = try FB2Writer(date: date).write(document, cover: cover)
        return try XMLDocument(data: data, options: [])
    }

    private func strings(_ doc: XMLDocument, _ xpath: String) throws -> [String] {
        try doc.nodes(forXPath: xpath).compactMap(\.stringValue)
    }

    private func document(author: String, language: String = "en") -> BookDocument {
        BookDocument(
            metadata: BookMetadata(title: "T", author: author, language: language),
            chapters: [Chapter(title: "C", blocks: [.paragraph([InlineRun("x")])])]
        )
    }

    private let titleInfo = "/*[local-name()='FictionBook']/*[local-name()='description']/*[local-name()='title-info']"

    @Test func isWellFormedXML() throws {
        let data = try FB2Writer(date: date).write(FixtureFactory.sampleDocument(), cover: FixtureFactory.pngImage(width: 3, height: 3, id: "cover"))
        _ = try XMLDocument(data: data, options: [])
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        #expect(!text.contains("\u{0B}"))
        #expect(data == (try FB2Writer(date: date).write(FixtureFactory.sampleDocument(), cover: FixtureFactory.pngImage(width: 3, height: 3, id: "cover"))))
    }

    @Test func authorSplitting() throws {
        var doc = try xml(document(author: "Анна Петрова"))
        #expect(try strings(doc, "\(titleInfo)/*[local-name()='author']/*[local-name()='first-name']") == ["Анна"])
        #expect(try strings(doc, "\(titleInfo)/*[local-name()='author']/*[local-name()='last-name']") == ["Петрова"])

        doc = try xml(document(author: "Вячеслав Николаевич Уточкин"))
        #expect(try strings(doc, "\(titleInfo)/*[local-name()='author']/*[local-name()='first-name']") == ["Вячеслав"])
        #expect(try strings(doc, "\(titleInfo)/*[local-name()='author']/*[local-name()='middle-name']") == ["Николаевич"])
        #expect(try strings(doc, "\(titleInfo)/*[local-name()='author']/*[local-name()='last-name']") == ["Уточкин"])

        doc = try xml(document(author: "Editor"))
        #expect(try strings(doc, "\(titleInfo)/*[local-name()='author']/*[local-name()='nickname']") == ["Editor"])

        doc = try xml(document(author: "  "))
        #expect(try strings(doc, "\(titleInfo)/*[local-name()='author']/*[local-name()='nickname']") == [""])
    }

    @Test func emptyAuthorIsAnEmptyNickname() throws {
        let data = try FB2Writer(date: date).write(document(author: ""), cover: nil)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("<title-info>\n<genre>prose</genre>\n<author><nickname/></author>"))
        #expect(!text.contains("Unknown"))
        let doc = try XMLDocument(data: data, options: [])
        #expect(try doc.nodes(forXPath: "\(titleInfo)/*[local-name()='author']").count == 1)
    }

    @Test func blankTitleAndLanguageGetFallbacks() throws {
        let document = BookDocument(
            metadata: BookMetadata(title: " ", author: "A", language: ""),
            chapters: [Chapter(title: "C", blocks: [.paragraph([InlineRun("x")])])]
        )
        let doc = try xml(document)
        #expect(try strings(doc, "\(titleInfo)/*[local-name()='book-title']") == ["Book"])
        #expect(try strings(doc, "\(titleInfo)/*[local-name()='lang']") == ["und"])
    }

    @Test func languageIsWritten() throws {
        let doc = try xml(document(author: "A", language: "ar"))
        #expect(try strings(doc, "\(titleInfo)/*[local-name()='lang']") == ["ar"])
    }

    @Test func partBlocksWrappedInUntitledSection() throws {
        let doc = try xml(FixtureFactory.sampleDocument())
        let first = "//*[local-name()='body']/*[local-name()='section'][1]"
        #expect(try doc.nodes(forXPath: "\(first)/*[local-name()='section'][1]/*[local-name()='title']").isEmpty)
        #expect(try strings(doc, "\(first)/*[local-name()='section'][1]/*[local-name()='p']") == ["Part intro."])
        #expect(try strings(doc, "\(first)/*[local-name()='section'][2]/*[local-name()='title']/*[local-name()='p']") == ["First"])
        // A section never mixes paragraphs with child sections.
        #expect(try doc.nodes(forXPath: "//*[local-name()='section'][*[local-name()='section'] and *[local-name()='p']]").isEmpty)
        #expect(try strings(doc, "\(first)/*[local-name()='section'][3]//*[local-name()='subtitle']") == ["Subheading"])
    }

    @Test func binariesReferencedExist() throws {
        let doc = try xml(FixtureFactory.sampleDocument(), cover: FixtureFactory.pngImage(width: 3, height: 3, id: "cover"))
        let hrefs = try doc.nodes(forXPath: "//*[@*[local-name()='href']]").compactMap { node -> String? in
            (node as? XMLElement)?.attributes?.first { $0.localName == "href" }?.stringValue
        }
        #expect(hrefs.count == 2)
        for href in hrefs {
            #expect(href.hasPrefix("#"))
            let id = String(href.dropFirst())
            #expect(try doc.nodes(forXPath: "//*[local-name()='binary'][@id='\(id)']").count == 1)
        }
        #expect(try doc.nodes(forXPath: "//*[local-name()='binary'][@content-type='image/png']").count == 2)
    }

    @Test func escapesText() throws {
        let doc = BookDocument(
            metadata: BookMetadata(title: "A & B", author: "X", language: "en"),
            chapters: [Chapter(title: "C", blocks: [.paragraph([InlineRun("a&<>b")]), .paragraph([])])]
        )
        let parsed = try xml(doc)
        #expect(try strings(parsed, "//*[local-name()='section']/*[local-name()='p']") == ["a&<>b"])
        #expect(try strings(parsed, "//*[local-name()='book-title']") == ["A & B"])
        #expect(try parsed.nodes(forXPath: "//*[local-name()='empty-line']").count == 1)
    }

    @Test func styledRunsAndDuplicateImageIDs() throws {
        let image = FixtureFactory.pngImage(width: 1, height: 1, id: "a b")
        let doc = BookDocument(
            metadata: BookMetadata(title: "T", author: "A", language: "en"),
            chapters: [
                Chapter(title: nil, blocks: [.paragraph([InlineRun("s", bold: true, italic: true)]), .image(image)]),
                Chapter(title: "Two", blocks: [.image(image)]),
            ]
        )
        let parsed = try xml(doc)
        #expect(try parsed.nodes(forXPath: "//*[local-name()='strong']/*[local-name()='emphasis']").count == 1)
        #expect(try parsed.nodes(forXPath: "//*[local-name()='binary']").count == 1)
    }
}
