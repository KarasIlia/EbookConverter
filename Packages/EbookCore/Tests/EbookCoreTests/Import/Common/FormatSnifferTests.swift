import Testing
import Foundation
@testable import EbookCore

@Suite struct FormatSnifferTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var name: String
        var data: Data
        var fileExtension: String
        var expected: SourceFormat?
        var testDescription: String { name }
    }

    static func zip(_ entries: [ZipEntry]) -> Data {
        (try? ZipWriter.archive(entries)) ?? Data()
    }

    static let cases: [Case] = [
        Case(name: "pdf", data: Data("%PDF-1.7\n%".utf8), fileExtension: "pdf", expected: .pdf),
        Case(name: "pdfNamedTxt", data: Data("%PDF-1.4 rest".utf8), fileExtension: "txt", expected: .pdf),
        Case(name: "epub", data: zip([
            ZipEntry(path: "mimetype", data: Data("application/epub+zip".utf8), method: .stored),
        ]), fileExtension: "epub", expected: .epub),
        Case(name: "docx", data: zip([
            ZipEntry(path: "word/document.xml", data: Data("<w:document/>".utf8)),
        ]), fileExtension: "docx", expected: .docx),
        Case(name: "docxNamedZip", data: zip([
            ZipEntry(path: "word/document.xml", data: Data("<w:document/>".utf8)),
        ]), fileExtension: "zip", expected: .docx),
        Case(name: "fb2ZipUnsupported", data: zip([
            ZipEntry(path: "book.fb2", data: Data("<?xml version=\"1.0\"?><FictionBook/>".utf8)),
        ]), fileExtension: "zip", expected: nil),
        Case(name: "rtf", data: Data("{\\rtf1\\ansi Hello}".utf8), fileExtension: "rtf", expected: .rtf),
        Case(name: "rtfNamedDoc", data: Data("{\\rtf1\\ansi Hello}".utf8), fileExtension: "doc", expected: .rtf),
        Case(name: "doc", data: Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0, 0, 0, 0]), fileExtension: "doc", expected: .doc),
        Case(name: "fb2", data: Data("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<FictionBook xmlns=\"x\"></FictionBook>".utf8), fileExtension: "fb2", expected: .fb2),
        Case(name: "fb2WithBOMAndWhitespace", data: Data([0xEF, 0xBB, 0xBF] + Array("  \n<?xml version=\"1.0\"?><FictionBook/>".utf8)), fileExtension: "xml", expected: .fb2),
        Case(name: "plainXMLIsText", data: Data("<?xml version=\"1.0\"?><note>hello</note>".utf8), fileExtension: "xml", expected: .txt),
        Case(name: "htmlDoctype", data: Data("<!DOCTYPE HTML PUBLIC><body>x</body>".utf8), fileExtension: "txt", expected: .html),
        Case(name: "htmlTag", data: Data("\n <HTML><body>x</body></HTML>".utf8), fileExtension: "htm", expected: .html),
        Case(name: "markdown", data: Data("# Title\n\ntext".utf8), fileExtension: "md", expected: .markdown),
        Case(name: "markdownLong", data: Data("# Title".utf8), fileExtension: "MARKDOWN", expected: .markdown),
        Case(name: "txt", data: Data("Just some text".utf8), fileExtension: "txt", expected: .txt),
        Case(name: "unknownExtensionText", data: Data("Just some text".utf8), fileExtension: "", expected: .txt),
        Case(name: "windows1251Text", data: Data([0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2, 0x20, 0xEC, 0xE8, 0xF0]), fileExtension: "txt", expected: .txt),
        Case(name: "utf16Text", data: Data([0xFF, 0xFE]) + Data("Hi there".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }), fileExtension: "txt", expected: .txt),
        Case(name: "binaryGarbage", data: Data([0x00, 0x01, 0x02, 0xFF, 0x00, 0x80, 0x00, 0x13]), fileExtension: "bin", expected: nil),
        Case(name: "binaryRenamedTxt", data: Data([0x41, 0x00, 0x00, 0x02, 0x03, 0x00, 0x7F, 0x00]), fileExtension: "txt", expected: nil),
    ]

    @Test(arguments: cases) func sniffsFormat(_ testCase: Case) {
        #expect(FormatSniffer.format(of: testCase.data, fileExtension: testCase.fileExtension) == testCase.expected)
    }

    @Test func emptyDataHasNoFormat() {
        #expect(FormatSniffer.format(of: Data(), fileExtension: "txt") == nil)
    }
}
