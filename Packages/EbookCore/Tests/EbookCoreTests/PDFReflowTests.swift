import Testing
import PDFKit
@testable import EbookCore

struct PDFReflowTests {
    private static let a4 = CGSize(width: 595, height: 842)
    private static let words = ["Alpha text.", "Beta text.", "Gamma text.", "Delta text."]

    /// A synthetic line whose baseline sits at `y`, `fontSize` tall.
    private func line(
        _ text: String, page: Int = 0, x: Double = 72, y: Double, width: Double = 400, fontSize: Double = 12, bold: Bool = false
    ) -> PDFTextLine {
        PDFTextLine(
            text: text, runs: [InlineRun(text, bold: bold)], pageIndex: page,
            bounds: CGRect(x: x, y: y, width: width, height: fontSize * 1.2),
            fontSize: fontSize, pageSize: Self.a4
        )
    }

    private func texts(_ lines: [PDFTextLine]) -> [String] {
        PDFReflow.paragraphs(from: lines).map(\.text)
    }

    @Test func joinsWrappedLines() {
        let result = texts([
            line("The quick brown fox", y: 700),
            line("jumps over the lazy", y: 686),
            line("dog.", y: 672),
        ])
        #expect(result == ["The quick brown fox jumps over the lazy dog."])
    }

    @Test(arguments: [
        ("разра-", "ботка", "разработка"),
        ("Санкт-", "Петербург", "Санкт-Петербург"),
        ("Silben-", "trennung", "Silbentrennung"),
        ("Silben\u{AD}", "trennung", "Silbentrennung"),
    ])
    func mergesHyphenation(first: String, second: String, expected: String) {
        let result = texts([line(first, y: 700), line(second, y: 686)])
        #expect(result == [expected])
    }

    @Test func joinsCJKWithoutSpace() {
        let result = texts([line("我们今天去", y: 700), line("公园散步。", y: 686)])
        #expect(result == ["我们今天去公园散步。"])
    }

    @Test func cjkTerminalBreaksParagraphAcrossPages() {
        let result = texts([
            line("我们今天去公园散步。", page: 0, y: 72),
            line("明天我们去学校。", page: 1, y: 770),
        ])
        #expect(result == ["我们今天去公园散步。", "明天我们去学校。"])
    }

    @Test func joinsAcrossPagesWithoutTerminal() {
        let result = texts([
            line("The sentence goes on", page: 0, y: 72),
            line("on the next page.", page: 1, y: 770),
        ])
        #expect(result == ["The sentence goes on on the next page."])
    }

    @Test func breaksOnIndent() {
        let result = texts([
            line("First paragraph line one", y: 700),
            line("ends here", y: 686),
            line("Second paragraph starts", x: 72 + 18, y: 672),
            line("and wraps back.", y: 658),
        ])
        #expect(result == ["First paragraph line one ends here", "Second paragraph starts and wraps back."])
    }

    @Test func indentedDialogueLinesStaySeparate() {
        let result = texts([
            line("The narrator speaks for a long while and the line", y: 700),
            line("ends with a full stop.", y: 686),
            line("— Yes, — he said.", x: 90, y: 672, width: 120),
            line("— No, — she said.", x: 90, y: 658, width: 120),
            line("Then the narrator continues his long tale and", y: 644),
            line("finishes it.", y: 630),
        ])
        #expect(result.count == 4)
        #expect(result[1] == "— Yes, — he said.")
    }

    @Test func breaksOnHangingIndent() {
        // Dictionary/bibliography layout: the first line hangs left of the column's body edge.
        let result = texts([
            line("affluent /ˈæfluːənt/ Adjective", x: 35, y: 700),
            line("if someone is affluent, they have a lot of money and", x: 53, y: 689),
            line("are able to live comfortably", x: 53, y: 678),
            line("base /beɪs/ Verb", x: 35, y: 667),
            line("if a business is based somewhere, that is where", x: 53, y: 656),
            line("its main offices are", x: 53, y: 645),
        ])
        #expect(result == [
            "affluent /ˈæfluːənt/ Adjective if someone is affluent, they have a lot of money and are able to live comfortably",
            "base /beɪs/ Verb if a business is based somewhere, that is where its main offices are",
        ])
    }

    @Test func breaksAfterShortLineWhenNextWordWouldHaveFit() {
        // Ragged-right lines: a line ending far before the column edge was ended on purpose.
        let result = texts([
            line("Collocates: an affluent suburb or neighbourhood", y: 700, width: 380),
            line("an affluent lifestyle", y: 689, width: 150),
            line("Egremont developed as an affluent residential area", y: 678, width: 390),
            line("in the early nineteenth century", y: 667, width: 230),
        ])
        #expect(result == [
            "Collocates: an affluent suburb or neighbourhood an affluent lifestyle",
            "Egremont developed as an affluent residential area in the early nineteenth century",
        ])
    }

    @Test func shortLineBeforeLongWordDoesNotBreak() {
        let result = texts([
            line("A justified line of text that runs the full width", y: 700, width: 400),
            line("of the column and then the next", y: 689, width: 330),
            line("extraordinarily long word continues the sentence.", y: 678, width: 400),
        ])
        #expect(result.count == 1)
    }

    @Test func breaksOnFontChange() {
        let paragraphs = PDFReflow.paragraphs(from: [
            line("Chapter heading", y: 720, fontSize: 20),
            line("Body text starts here", y: 690),
            line("and continues.", y: 676),
        ])
        #expect(paragraphs.map(\.text) == ["Chapter heading", "Body text starts here and continues."])
        #expect(paragraphs.map(\.fontSize) == [20, 12])
    }

    @Test func breaksOnLargeVerticalGap() {
        let result = texts([
            line("One", y: 700), line("two", y: 686), line("three", y: 672),
            line("Four", y: 630), line("five", y: 616),
        ])
        #expect(result == ["One two three", "Four five"])
    }

    @Test func breaksBetweenBoldAndPlainLines() {
        let paragraphs = PDFReflow.paragraphs(from: [
            line("affluent", y: 700, bold: true),
            line("having a lot of money", y: 686),
            line("Next headword", y: 672, bold: true),
        ])
        #expect(paragraphs.map(\.text) == ["affluent", "having a lot of money", "Next headword"])
        #expect(paragraphs.map(\.isAllBold) == [true, false, true])
    }

    @Test func columnChangeBreaksOnlyAfterTerminal() {
        let result = texts([
            line("Left column ends", x: 50, y: 100),
            line("mid sentence", x: 310, y: 770),
            line("and then stops.", x: 310, y: 756),
            line("Next paragraph", x: 50, y: 700, fontSize: 12),
        ])
        // The last line jumps back left and up a column: a new paragraph after a terminal.
        #expect(result == ["Left column ends mid sentence and then stops.", "Next paragraph"])
    }

    @Test func removesRunningHeadersAndPageNumbers() {
        var lines: [PDFTextLine] = []
        for page in 0..<4 {
            lines.append(line(Self.words[page], page: page, y: 600))
            lines.append(line("Book Title \(page + 10)", page: page, y: 400))
            lines.append(line("\(page + 1)", page: page, y: 30))
            lines.append(line(["i", "ii", "iii", "iv"][page], page: page, y: 800))
        }
        let kept = PDFReflow.removingRunningHeaders(lines).map(\.text)
        #expect(kept == Self.words)
    }

    @Test func keepsRepeatedLinesOnFewPages() {
        let lines = (0..<2).map { line("Repeated", page: $0, y: 800) }
            + (2..<10).map { line("Other text \(["a", "b", "c", "d", "e", "f", "g", "h"][$0 - 2])", page: $0, y: 600) }
        #expect(PDFReflow.removingRunningHeaders(lines).count == 10)
    }

    @Test func twoColumnPageWithHeaders() throws {
        let header = "Practice Workbook Unit 2"
        // Distinct words per page: digits alone would make the body lines look like a repeated header.
        let names = ["", "One", "Two", "Three"]
        var pages: [[FixtureTextBox]] = []
        for page in 1...3 {
            func box(_ text: String, x: Double, y: Double) -> FixtureTextBox {
                FixtureTextBox(text, rect: CGRect(x: x, y: y, width: 240, height: 12), fontSize: 10)
            }
            pages.append([
                box("Left \(names[page]) column text that", x: 50, y: 700),
                box("wraps onto line \(names[page]).", x: 50, y: 688),
                // PDFKit sees the header in the middle of the content stream, geometry puts it at the top.
                box(header, x: 50, y: 810),
                box("Right \(names[page]) column text that", x: 310, y: 700),
                box("also wraps over \(names[page]).", x: 310, y: 688),
                box("\(page)", x: 290, y: 30),
            ])
        }
        let url = try FixtureFactory.pdf(pages: pages)
        let document = try #require(PDFDocument(url: url))
        let lines = PDFReflow.removingRunningHeaders(PDFLineExtractor.lines(in: document))
        let paragraphs = PDFReflow.paragraphs(from: lines).map(\.text)

        #expect(!paragraphs.contains { $0.contains("Practice Workbook") })
        #expect(!paragraphs.contains { $0.trimmingCharacters(in: .whitespaces).allSatisfy(\.isNumber) })
        for page in 1...3 {
            let left = "Left \(names[page]) column text that wraps onto line \(names[page])."
            let right = "Right \(names[page]) column text that also wraps over \(names[page])."
            let leftIndex = try #require(paragraphs.firstIndex(of: left))
            let rightIndex = try #require(paragraphs.firstIndex(of: right))
            #expect(leftIndex < rightIndex)
        }
    }
}
