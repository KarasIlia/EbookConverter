import Testing
@testable import EbookCore

@Suite struct TableOfContentsLabelTests {
    @Test func titledChapterUsesItsTitle() {
        #expect(TableOfContentsLabel.label(for: Chapter(title: "One"), isFirst: true, bookTitle: "Book") == "One")
        #expect(TableOfContentsLabel.heading(of: Chapter(title: "One")) == "One")
    }

    @Test func firstUntitledChapterUsesBookTitle() {
        #expect(TableOfContentsLabel.label(for: Chapter(), isFirst: true, bookTitle: "My Book") == "My Book")
        #expect(TableOfContentsLabel.label(for: Chapter(title: "  "), isFirst: true, bookTitle: "My Book") == "My Book")
    }

    @Test func laterUntitledChapterUsesEllipsis() {
        #expect(TableOfContentsLabel.label(for: Chapter(), isFirst: false, bookTitle: "My Book") == "\u{2026}")
    }

    @Test func blankTitleHasNoHeading() {
        #expect(TableOfContentsLabel.heading(of: Chapter(title: " \n")) == nil)
        #expect(TableOfContentsLabel.heading(of: Chapter()) == nil)
    }

    @Test func epubWriterUsesSameLabelsForBlankTitles() throws {
        let document = BookDocument(
            metadata: BookMetadata(title: "Book", author: "", language: "en"),
            chapters: [Chapter(title: " ", blocks: [.paragraph([InlineRun("one")])])]
        )
        let data = try EPUBWriter().write(document, cover: nil)
        let nav = String(decoding: try ZipReader(data: data).data(for: "OEBPS/nav.xhtml"), as: UTF8.self)
        #expect(nav.contains(">Book</a>"))
    }
}
