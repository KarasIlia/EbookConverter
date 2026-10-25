import Testing
import Foundation
@testable import EbookCore

@Suite struct StructureBuilderTests {
    // MARK: Helpers

    private func para(_ text: String, size: Double? = nil, bold: Bool = false, hint: Int? = nil) -> StructuredItem {
        .paragraph(StyledParagraph(runs: [InlineRun(text, bold: bold)], fontSize: size, headingLevelHint: hint))
    }

    private let body = "This is ordinary body text that is long enough to dominate the character count of the page."

    private func headingCount(in chapter: Chapter, level: Int) -> Int {
        chapter.blocks.filter { block in
            if case .heading(let l, _) = block { l == level } else { false }
        }.count
    }

    // MARK: Patterns

    @Test(arguments: [
        "Глава 1", "ГЛАВА ПЕРВАЯ", "Chapter XII", "Kapitel 3", "Chapitre 2", "Capítulo 4",
        "Rozdział 5", "第一章", "第12回", "IV", "Пролог", "Vorwort",
    ])
    func patternsAreMultilingualChapter(_ line: String) {
        #expect(HeadingPatterns.partOrChapter(line) == .chapter)
    }

    @Test(arguments: ["Часть 2", "Teil 1", "Part One"])
    func patternsAreMultilingualPart(_ line: String) {
        #expect(HeadingPatterns.partOrChapter(line) == .part)
    }

    @Test(arguments: ["Глава была длинной.", "Chapter and verse are quoted here."])
    func patternsRejectSentences(_ line: String) {
        #expect(HeadingPatterns.partOrChapter(line) == nil)
    }

    @Test(arguments: [
        "CHAPTER 1. The Beginning", "Глава 3 — Возвращение", "Глава 7.", "  chapitre deux  ",
        "第3章 风起", "제 2 장", "Κεφάλαιο 1", "פרק 3", "الفصل الأول",
    ])
    func patternsAcceptSubtitlesAndScripts(_ line: String) {
        #expect(HeadingPatterns.partOrChapter(line) == .chapter)
    }

    @Test(arguments: ["mix", "Dim", "12345", "Chapter", "Глава 1 была"])
    func patternsRejectNonHeadings(_ line: String) {
        #expect(HeadingPatterns.partOrChapter(line) == nil)
    }

    // MARK: Builder

    @Test func fontSizeHeadingsSplitChapters() {
        let items = [para("Beginning", size: 18), para(body, size: 12), para("Ending", size: 18), para(body, size: 12)]
        let result = StructureBuilder.build(items)
        #expect(result.foundHeadings)
        #expect(result.chapters.map(\.title) == ["Beginning", "Ending"])
        #expect(result.chapters.allSatisfy { $0.blocks == [.paragraph([InlineRun(body)])] })
    }

    @Test func partsAndChaptersNest() {
        let items = [
            para("Часть 1"), para("Глава 1"), para("Текст первой главы."),
            para("Глава 2"), para("Текст второй главы."), para("Часть 2"), para("Глава 3"),
        ]
        let result = StructureBuilder.build(items)
        #expect(result.foundHeadings)
        #expect(result.chapters.map(\.title) == ["Часть 1", "Часть 2"])
        #expect(result.chapters[0].children.map(\.title) == ["Глава 1", "Глава 2"])
        #expect(result.chapters[1].children.map(\.title) == ["Глава 3"])
        #expect(result.chapters[0].children[1].plainText == "Текст второй главы.")
    }

    @Test func boldBodySizeLinesBecomeSubheadingsWhenLargerTierExists() {
        var items = [para("Vocabulary Builder", size: 50)]
        for index in 1...30 {
            items.append(para("headword\(index)", size: 10, bold: true))
            items.append(para(body, size: 10))
        }
        let result = StructureBuilder.build(items)
        #expect(result.foundHeadings)
        #expect(result.chapters.count == 1)
        #expect(result.chapters.first?.title == "Vocabulary Builder")
        if let chapter = result.chapters.first {
            #expect(headingCount(in: chapter, level: 3) == 30)
            #expect(chapter.blocks.first == .heading(level: 3, runs: [InlineRun("headword1", bold: true)]))
        }
    }

    @Test func boldOnlyLinesSplitWhenNoOtherTier() {
        let items = [
            para("ПОСВЯЩЕНИЕ", size: 12, bold: true), para(body, size: 12),
            para("ОТ АВТОРА", size: 12, bold: true), para(body, size: 12),
        ]
        let result = StructureBuilder.build(items)
        #expect(result.foundHeadings)
        #expect(result.chapters.map(\.title) == ["ПОСВЯЩЕНИЕ", "ОТ АВТОРА"])
        #expect(result.chapters.allSatisfy { headingCount(in: $0, level: 3) == 0 })
    }

    @Test func leadingTextBecomesUntitledChapter() {
        let items = [para("Foreword text before anything."), para("Chapter 1"), para(body)]
        let result = StructureBuilder.build(items)
        #expect(result.chapters.map(\.title) == [nil, "Chapter 1"])
        #expect(result.chapters[0].plainText == "Foreword text before anything.")
    }

    @Test func noHeadingsYieldsSingleChapter() {
        let items = [para(body, size: 12), para("", size: 12), para(body, size: 12)]
        let result = StructureBuilder.build(items)
        #expect(result.foundHeadings == false)
        #expect(result.chapters.count == 1)
        #expect(result.chapters.first?.title == nil)
        #expect(result.chapters.first?.blocks.count == 2)
    }

    @Test func longBoldParagraphIsNotHeading() {
        let long = String(repeating: "word ", count: 40)
        #expect(long.count == 200)
        let result = StructureBuilder.build([para(long, size: 12, bold: true), para(body, size: 12)])
        #expect(result.foundHeadings == false)
        #expect(result.chapters.first?.blocks.first == .paragraph([InlineRun(long, bold: true)]))
    }

    @Test func emptyInputYieldsNoChapters() {
        let result = StructureBuilder.build([])
        #expect(result.chapters.isEmpty)
        #expect(result.foundHeadings == false)
    }

    @Test func headingLevelHintsDriveHierarchy() {
        let items = [
            para("Book", hint: 1), para("Intro", hint: 2), para(body),
            para("Detail", hint: 3), para(body),
        ]
        let result = StructureBuilder.build(items)
        #expect(result.chapters.map(\.title) == ["Book"])
        #expect(result.chapters[0].children.map(\.title) == ["Intro"])
        #expect(result.chapters[0].children[0].blocks[1] == .heading(level: 3, runs: [InlineRun("Detail")]))
    }

    @Test func smallerSizeThanPatternChaptersBecomesSubheading() {
        let items = [
            para("Chapter 1", size: 16), para(body, size: 11), para("A section", size: 13), para(body, size: 11),
            para("Chapter 2", size: 16), para(body, size: 11),
        ]
        let result = StructureBuilder.build(items)
        #expect(result.chapters.map(\.title) == ["Chapter 1", "Chapter 2"])
        #expect(result.chapters[0].blocks[1] == .heading(level: 3, runs: [InlineRun("A section")]))
    }

    @Test func imagesAndSentenceLinesStayInChapter() {
        let image = ImageAsset(id: "i1", data: Data([1]), contentType: .png, pixelWidth: 1, pixelHeight: 1)
        let items: [StructuredItem] = [para("Chapter 1"), .image(image), para("Short bold line.", bold: true)]
        let result = StructureBuilder.build(items)
        #expect(result.chapters.count == 1)
        #expect(result.chapters[0].blocks == [.image(image), .paragraph([InlineRun("Short bold line.", bold: true)])])
    }

    @Test func styledParagraphTextAndBold() {
        let mixed = StyledParagraph(runs: [InlineRun("A", bold: true), InlineRun(" "), InlineRun("B", bold: true)])
        #expect(mixed.text == "A B")
        #expect(mixed.isAllBold)
        #expect(StyledParagraph(runs: [InlineRun("A", bold: true), InlineRun("b")]).isAllBold == false)
        #expect(StyledParagraph(runs: []).isAllBold == false)
    }

    // MARK: Fix round 1

    @Test(arguments: ["Книга упала.", "Часть меня.", "Book it.", "Del mismo.", "Глава семьи."])
    func keywordSentencesAreNotHeadings(_ sentence: String) throws {
        #expect(HeadingPatterns.partOrChapter(sentence) == nil)
        let items = [
            para("Глава 1", size: 12), para(body, size: 12), para(sentence, size: 12),
            para(body, size: 12), para("Глава 2", size: 12), para(body, size: 12),
        ]
        let result = StructureBuilder.build(items)
        try #require(result.chapters.map(\.title) == ["Глава 1", "Глава 2"])
        #expect(result.chapters.allSatisfy { $0.children.isEmpty })
        #expect(result.chapters[0].blocks[1] == .paragraph([InlineRun(sentence)]))
    }

    @Test func wordTokenWithoutPeriodIsPart() {
        #expect(HeadingPatterns.partOrChapter("Часть первая") == .part)
        let items = [para("Часть первая"), para("Глава 1"), para(body)]
        let result = StructureBuilder.build(items)
        #expect(result.chapters.map(\.title) == ["Часть первая"])
        #expect(result.chapters[0].children.map(\.title) == ["Глава 1"])
    }

    @Test func boldWordTokenWithPeriodIsChapter() {
        #expect(HeadingPatterns.partOrChapter("Глава первая.") == nil)
        let items = [para("Вступление.", size: 12), para("Глава первая.", size: 12, bold: true), para(body, size: 12)]
        let result = StructureBuilder.build(items)
        #expect(result.foundHeadings)
        #expect(result.chapters.map(\.title) == [nil, "Глава первая."])
    }

    @Test(arguments: [("KISIM 2", HeadingKind.part), ("Kısım 2", .part), ("BÖLÜM 3", .chapter), ("Bölüm 3", .chapter)])
    func turkishDotlessIFolds(_ line: String, _ expected: HeadingKind) {
        #expect(HeadingPatterns.partOrChapter(line) == expected)
    }

    @Test func sizeEqualToPatternHeadingSharesItsLevel() {
        let items = [
            para("Chapter 1", size: 16), para(body, size: 11),
            para("Interlude", size: 16), para(body, size: 11),
            para("Chapter 2", size: 16), para(body, size: 11),
        ]
        let result = StructureBuilder.build(items)
        #expect(result.chapters.map(\.title) == ["Chapter 1", "Interlude", "Chapter 2"])
        #expect(result.chapters.allSatisfy { $0.children.isEmpty })
    }

    @Test func blocksBeforeFirstChapterOfPartGoToPart() {
        let items = [para("Part 1"), para("Part epigraph text."), para("Chapter 1"), para(body)]
        let result = StructureBuilder.build(items)
        #expect(result.chapters.map(\.title) == ["Part 1"])
        #expect(result.chapters[0].blocks == [.paragraph([InlineRun("Part epigraph text.")])])
        #expect(result.chapters[0].children.map(\.title) == ["Chapter 1"])
        #expect(result.chapters[0].children[0].plainText == body)
    }

    @Test func explicitHeadingHintBypassesTerminalPunctuation() {
        let chapters = StructureBuilder.build([para("Note:", hint: 2), para(body), para("Next", hint: 2), para(body)]).chapters
        #expect(chapters.map(\.title) == ["Note:", "Next"])
    }

    @Test func unhintedLineWithTerminalPunctuationStaysBody() {
        let result = StructureBuilder.build([para("Note:", bold: true), para(body)])
        #expect(!result.foundHeadings)
    }
}
