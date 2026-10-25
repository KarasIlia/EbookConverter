import Testing
import PDFKit
@testable import EbookCore

struct PDFLineExtractorTests {
    private func extract(_ pages: [[FixtureTextBox]]) throws -> [PDFTextLine] {
        let url = try FixtureFactory.pdf(pages: pages)
        let document = try #require(PDFDocument(url: url))
        return PDFLineExtractor.lines(in: document)
    }

    @Test func extractsLinesWithBounds() throws {
        let lines = try extract([[
            FixtureTextBox("First line of text", rect: CGRect(x: 72, y: 700, width: 400, height: 16)),
            FixtureTextBox("Вторая строка текста", rect: CGRect(x: 72, y: 680, width: 400, height: 16)),
        ]])
        #expect(lines.count == 2)
        #expect(lines[0].text == "First line of text")
        #expect(lines[1].text == "Вторая строка текста")
        #expect(lines[0].bounds.minY > lines[1].bounds.minY)
        #expect(abs(lines[0].bounds.minX - 72) < 3)
        #expect(lines[0].pageSize == CGSize(width: 595, height: 842))
    }

    @Test func extractsFontSizeAndBold() throws {
        let lines = try extract([[
            FixtureTextBox("Big Title", rect: CGRect(x: 72, y: 700, width: 400, height: 30), fontSize: 24, bold: true),
            FixtureTextBox("Body text here", rect: CGRect(x: 72, y: 650, width: 400, height: 14), fontSize: 10),
        ]])
        #expect(lines.count == 2)
        #expect(abs(lines[0].fontSize - 24) <= 0.5)
        #expect(lines[0].runs.allSatisfy { $0.isBold })
        #expect(lines[0].runs.map(\.text).joined() == "Big Title")
        #expect(abs(lines[1].fontSize - 10) <= 0.5)
        #expect(lines[1].runs.allSatisfy { !$0.isBold })
    }

    @Test func keepsPageIndex() throws {
        let lines = try extract([
            [FixtureTextBox("Page one", rect: CGRect(x: 72, y: 700, width: 300, height: 16))],
            [FixtureTextBox("Page two", rect: CGRect(x: 72, y: 700, width: 300, height: 16))],
        ])
        #expect(lines.map(\.pageIndex) == [0, 1])
    }
}
