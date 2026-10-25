import Testing
import Foundation
@testable import EbookCore

@Suite struct TXTImporterTests {
    private func write(_ text: String, name: String = "book.txt", encoding: String.Encoding = .utf8) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: name)
        try #require(text.data(using: encoding)).write(to: url)
        return url
    }

    private func importBook(_ text: String, name: String = "book.txt", encoding: String.Encoding = .utf8) async throws -> ImportResult {
        try await TXTImporter().importBook(from: write(text, name: name, encoding: encoding), context: ImportContext())
    }

    @Test func txtSplitsChaptersByPattern() async throws {
        let p = TextEncodingTests.russian
        let result = try await importBook("Глава 1\n\n\(p)\n\nГлава 2\n\n\(p)")
        #expect(result.document.chapters.map(\.title) == ["Глава 1", "Глава 2"])
        #expect(result.document.metadata.language == "ru")
        #expect(!result.warnings.contains(.noChaptersFound))
        #expect(!result.warnings.contains(.languageUndetermined))
    }

    @Test func txtSplitsGermanChapters() async throws {
        let p = TextEncodingTests.german
        let result = try await importBook("Kapitel 1\n\n\(p)\n\nKapitel 2\n\n\(p)")
        #expect(result.document.chapters.map(\.title) == ["Kapitel 1", "Kapitel 2"])
        #expect(result.document.metadata.language == "de")
    }

    @Test func txtDecodesWindows1251AndTitlesFromFilename() async throws {
        let result = try await importBook(TextEncodingTests.russian, name: "my_book.txt", encoding: .windowsCP1251)
        #expect(result.document.metadata.title == "my book")
        #expect(result.document.metadata.author == "")
        #expect(result.document.metadata.language == "ru")
    }

    @Test func txtWithoutHeadingsWarns() async throws {
        let result = try await importBook("First line of text here.\nSecond line of text here.")
        #expect(result.warnings.contains(.noChaptersFound))
        #expect(result.document.chapters.count == 1)
        #expect(result.document.chapters[0].blocks.count == 2)
    }

    @Test func undeterminedLanguageWarns() async throws {
        let result = try await importBook("12345")
        #expect(result.document.metadata.language == "und")
        #expect(result.warnings.contains(.languageUndetermined))
    }

    @Test func uppercaseShortLineBecomesHeading() async throws {
        let p = TextEncodingTests.russian
        let result = try await importBook("\(p)\n\nПОСВЯЩЕНИЕ\n\n\(p)\n\n\(p)\n\n\(p)\n\n\(p)")
        #expect(result.document.chapters.map(\.title).contains("ПОСВЯЩЕНИЕ"))
    }

    @Test func manyCapitalsLinesAreSpeakerNamesNotHeadings() async throws {
        let line = "To be, or not to be, that is the question."
        let text = (0..<5).map { _ in "HAMLET\n\n\(line)" }.joined(separator: "\n\n")
        let result = try await importBook(text)
        #expect(result.warnings.contains(.noChaptersFound))
    }

    @Test func uncasedScriptNeverGetsUppercaseHint() async throws {
        let p = TextEncodingTests.japanese
        let result = try await importBook("\(p)\n\n東京\n\n\(p)")
        #expect(result.warnings.contains(.noChaptersFound))
    }

    @Test func emptyTxtThrows() async throws {
        let url = try write("  \n\n \n")
        await #expect(throws: ImportError.emptyDocument) {
            try await TXTImporter().importBook(from: url, context: ImportContext())
        }
    }

    // MARK: - Paragraph splitting

    /// Greedy word wrap at `width` characters; `indent` precedes each paragraph's first line.
    private func wrapped(_ paragraph: String, width: Int, indent: String = "") -> String {
        var lines: [String] = []
        var line = indent
        for word in paragraph.split(separator: " ") {
            if line.count + word.count + 1 > width, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append(line)
                line = ""
            }
            line += (line.isEmpty || line == indent ? "" : " ") + word
        }
        lines.append(line)
        return lines.joined(separator: "\n")
    }

    private func paragraphTexts(_ chapter: Chapter) -> [String] {
        chapter.blocks.compactMap { block in
            if case .paragraph(let runs) = block { runs.map(\.text).joined() } else { nil }
        }
    }

    @Test func headingDirectlyFollowedByTextIsChapter() async throws {
        let result = try await importBook("Глава 1\nтекст.")
        #expect(result.document.chapters.map(\.title) == ["Глава 1"])
        #expect(paragraphTexts(result.document.chapters[0]) == ["текст."])
    }

    @Test func cjkHeadingDirectlyFollowedByTextIsChapter() async throws {
        let result = try await importBook("第一章\n正文。")
        #expect(result.document.chapters.map(\.title) == ["第一章"])
        #expect(paragraphTexts(result.document.chapters[0]) == ["正文。"])
    }

    @Test func hardWrappedHeadingGluedToTextIsChapter() async throws {
        let p = TextEncodingTests.russian
        let body = wrapped(p, width: 70)
        let result = try await importBook("Глава 1\n\(body)\n\nГлава 2\n\(body)\n")
        #expect(result.document.chapters.map(\.title) == ["Глава 1", "Глава 2"])
        let first = paragraphTexts(result.document.chapters[0])
        #expect(first == [p.trimmingCharacters(in: .whitespaces)])
    }

    @Test func hardWrappedCJKHeadingGluedToTextIsChapter() async throws {
        let p = String(repeating: "这是一个很长的中文段落用于测试行的连接是否正确。", count: 6)
        let lines = stride(from: 0, to: p.count, by: 30).map { start in
            String(p.dropFirst(start).prefix(30))
        }
        let body = "\u{3000}\u{3000}" + lines.joined(separator: "\n")
        let result = try await importBook("第一章\n\(body)\n第二章\n\(body)")
        #expect(result.document.chapters.map(\.title) == ["第一章", "第二章"])
        #expect(paragraphTexts(result.document.chapters[0]) == [p])
    }

    @Test func onePerLineWithBlankLinesAroundHeadingsKeepsParagraphs() async throws {
        let lines = [
            "Она открыла дверь и долго смотрела на пустую улицу, по которой ветер гнал сухие листья и обрывки газет.",
            "— Ты идёшь? — спросил он.",
            "Никто не ответил, и только часы на стене продолжали отсчитывать минуты, одну за другой, без остановки.",
            "Потом наступила тишина, такая плотная, что казалось, её можно потрогать рукой.",
        ]
        let block = lines.joined(separator: "\n")
        let result = try await importBook("Глава 1\n\n\(block)\n\nГлава 2\n\n\(block)")
        #expect(result.document.chapters.map(\.title) == ["Глава 1", "Глава 2"])
        #expect(paragraphTexts(result.document.chapters[0]) == lines)
        #expect(paragraphTexts(result.document.chapters[1]) == lines)
    }

    @Test func hardWrappedIndentedParagraphsSplitAtIndents() async throws {
        let paragraphs = [
            "It was a bright cold day in April and the clocks were striking thirteen while the wind blew dust along the street.",
            "Winston Smith slipped quickly through the glass doors of Victory Mansions though not quickly enough to prevent a swirl of gritty dust from entering along with him.",
            "The hallway smelt of boiled cabbage and old rag mats and at one end of it a coloured poster too large for indoor display had been tacked to the wall.",
        ]
        let text = paragraphs.map { wrapped($0, width: 60, indent: "    ") }.joined(separator: "\n")
        let result = try await importBook(text)
        #expect(result.document.chapters.count == 1)
        #expect(paragraphTexts(result.document.chapters[0]) == paragraphs)
    }

    @Test func hardWrappedParagraphsSplitAtBlankLines() async throws {
        let paragraphs = [
            "It was a bright cold day in April and the clocks were striking thirteen while the wind blew dust along the street",
            "Winston Smith slipped quickly through the glass doors of Victory Mansions though not quickly enough to prevent a swirl",
        ]
        let text = paragraphs.map { wrapped($0, width: 60) }.joined(separator: "\n\n")
        let result = try await importBook(text)
        #expect(paragraphTexts(result.document.chapters[0]) == paragraphs)
    }

    @Test func hardWrappedParagraphsSplitAfterShortSentenceEnd() async throws {
        let text = """
            It was a bright cold day in April and the clocks were striking
            thirteen while the wind blew dust along the empty street.
            Winston Smith slipped quickly through the glass doors of the
            Victory Mansions though not quickly enough to prevent it.
            The hallway smelt of boiled cabbage and old rag mats and at
            one end of it a coloured poster had been tacked to the wall.
            """
        let result = try await importBook(text)
        #expect(paragraphTexts(result.document.chapters[0]).count == 1)
        let split = text.replacing("thirteen while the wind blew dust along the empty street.", with: "thirteen.")
        let splitResult = try await importBook(split)
        #expect(paragraphTexts(splitResult.document.chapters[0]).count == 2)
    }

    @Test func hardWrappedHyphenationIsRepaired() async throws {
        let text = """
            The quick brown fox jumps over the lazy dog and then it con-
            tinues running across the field until it reaches the river.
            The quick brown fox jumps over the lazy dog and then it runs
            across the field until it reaches the river where it stops.
            """
        let result = try await importBook(text)
        let texts = paragraphTexts(result.document.chapters[0])
        #expect(texts.count == 1)
        #expect(texts.first?.contains("continues") == true)
    }

    @Test func romanNumeralWordInsideWrappedParagraphIsNotChapter() async throws {
        let text = """
            The results of the experiment were exactly as the figure shown in
            I
            think the second table that we published in the previous report.
            Then the quick brown fox jumps over the lazy dog and it runs away
            across the wide field until it reaches the river where it stops.
            """
        let result = try await importBook(text)
        #expect(result.warnings.contains(.noChaptersFound))
        #expect(paragraphTexts(result.document.chapters[0]).count == 1)
    }

    @Test func headingKeywordInsideSentenceIsNotChapter() async throws {
        let result = try await importBook("Глава 1 текст")
        #expect(result.warnings.contains(.noChaptersFound))
        #expect(result.document.chapters.map(\.title) == [nil])
    }
}
