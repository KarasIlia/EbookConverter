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
        let result = try await importBook("\(p)\n\nПОСВЯЩЕНИЕ\n\n\(p)")
        #expect(result.document.chapters.map(\.title).contains("ПОСВЯЩЕНИЕ"))
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
}
