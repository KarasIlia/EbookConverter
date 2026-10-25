import Testing
import Foundation
@testable import EbookCore

@Suite struct BookConverterTests {
    private func folder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func file(_ data: Data, name: String, in dir: URL? = nil) throws -> URL {
        let url = try (dir ?? folder()).appending(path: name)
        try data.write(to: url)
        return url
    }

    @Test func emptyFileThrowsEmptyDocument() async throws {
        let url = try file(Data(), name: "empty.txt")
        await #expect(throws: ImportError.emptyDocument) {
            try await BookConverter().importBook(from: url, context: ImportContext())
        }
    }

    @Test func binaryGarbageThrowsUnsupported() async throws {
        let url = try file(Data([0x00, 0x01, 0x02, 0xFF, 0x00, 0x80]), name: "junk.bin")
        await #expect(throws: ImportError.unsupportedFormat) {
            try await BookConverter().importBook(from: url, context: ImportContext())
        }
    }

    @Test func binaryRenamedTxtThrowsUnsupported() async throws {
        let url = try file(Data((0..<64).map { UInt8($0 % 4) } + [0x41, 0x42]), name: "book.txt")
        await #expect(throws: ImportError.unsupportedFormat) {
            try await BookConverter().importBook(from: url, context: ImportContext())
        }
    }

    @Test func missingFileIsUnreadable() async throws {
        let url = try folder().appending(path: "nope.txt")
        await #expect(throws: ImportError.self) {
            try await BookConverter().importBook(from: url, context: ImportContext())
        }
    }

    @Test func importRunsCoverDetection() async throws {
        let dir = try folder()
        try FixtureFactory.pngImage(width: 400, height: 600).data.write(to: dir.appending(path: "cover.png"))
        let url = try file(Data("![cover](cover.png)\n\n## Chapter\n\nSome text of the book.".utf8), name: "book.md", in: dir)
        let result = try await BookConverter().importBook(from: url, context: ImportContext(accessibleFolder: dir))
        let cover = try #require(result.sourceCover)
        #expect(cover.pixelWidth == 400 && cover.pixelHeight == 600)
        #expect(result.document.allImages.isEmpty)
    }

    @Test func txtImportsThroughFacade() async throws {
        let url = try file(Data("Hello world, this is a plain text book.".utf8), name: "a.txt")
        let result = try await BookConverter().importBook(from: url, context: ImportContext())
        #expect(!result.document.chapters.isEmpty)
        #expect(result.sourceCover == nil)
    }

    @Test func rtfNamedDocImports() async throws {
        let url = try file(Data("{\\rtf1\\ansi Hello rtf world.}".utf8), name: "a.doc")
        let result = try await BookConverter().importBook(from: url, context: ImportContext())
        #expect(!result.document.chapters.isEmpty)
    }

    @Test func fb2ZipIsUnsupported() async throws {
        let archive = try ZipWriter.archive([ZipEntry(path: "b.fb2", data: Data("<FictionBook/>".utf8))])
        let url = try file(archive, name: "b.fb2.zip")
        await #expect(throws: ImportError.unsupportedFormat) {
            try await BookConverter().importBook(from: url, context: ImportContext())
        }
    }

    @Test func writeProducesBothFormats() throws {
        let converter = BookConverter()
        let document = FixtureFactory.sampleDocument()
        let epub = try converter.write(document, cover: nil, as: .epub)
        let fb2 = try converter.write(document, cover: nil, as: .fb2)
        #expect(epub.starts(with: Data("PK".utf8)))
        #expect(String(decoding: fb2, as: UTF8.self).contains("<FictionBook"))
    }

    @Test func fixedDateMakesOutputRepeatable() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let converter = BookConverter(fixedDate: date)
        let document = FixtureFactory.sampleDocument()
        for format in OutputFormat.allCases {
            let first = try converter.write(document, cover: nil, as: format)
            let second = try BookConverter(fixedDate: date).write(document, cover: nil, as: format)
            #expect(first == second)
        }
    }
}
