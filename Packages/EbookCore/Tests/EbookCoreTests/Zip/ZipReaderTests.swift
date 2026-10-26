import Foundation
import Testing
@testable import EbookCore

@Suite struct ZipReaderTests {
    private static let text = String(repeating: "Привет, мир! ", count: 200)

    private func le16(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)] }
    private func le32(_ value: Int) -> [UInt8] { le16(value & 0xFFFF) + le16((value >> 16) & 0xFFFF) }

    @Test func zipRoundTrip() throws {
        let png = FixtureFactory.pngImage(width: 4, height: 4).data
        let entries = [
            ZipEntry(path: "mimetype", data: Data("application/epub+zip".utf8), method: .stored),
            ZipEntry(path: "dir/text.txt", data: Data(Self.text.utf8), method: .deflated),
            ZipEntry(path: "dir/image.png", data: png, method: .stored),
            ZipEntry(path: "empty.txt", data: Data(), method: .deflated),
        ]
        let reader = try ZipReader(data: ZipWriter.archive(entries))
        #expect(reader.paths == entries.map(\.path))
        for entry in entries {
            #expect(try reader.data(for: entry.path) == entry.data)
        }
        #expect(throws: ImportError.self) { try reader.data(for: "missing") }
    }

    @Test func zipReaderRejectsGarbage() {
        #expect(throws: ImportError.self) { try ZipReader(data: Data("definitely not a zip file at all".utf8)) }
        #expect(throws: ImportError.self) { try ZipReader(data: Data()) }
    }

    @Test func rejectsCorruptedContent() throws {
        var zip = try ZipWriter.archive([ZipEntry(path: "a.txt", data: Data("hello world".utf8), method: .stored)])
        zip[30 + 5] ^= 0xFF // first payload byte, after the 5-byte name
        let reader = try ZipReader(data: zip)
        #expect(throws: ImportError.self) { try reader.data(for: "a.txt") }
    }

    @Test func rejectsTruncatedArchive() throws {
        let zip = try ZipWriter.archive([ZipEntry(path: "a.txt", data: Data(Self.text.utf8))])
        #expect(throws: ImportError.self) { try ZipReader(data: zip.prefix(zip.count - 10)) }
    }

    @Test func readsEntriesWithDataDescriptor() throws {
        let content = Data(Self.text.utf8)
        let compressed = try (content as NSData).compressed(using: .zlib) as Data
        let crc = Int(CRC32.checksum(content))
        let name = Array("d.txt".utf8)

        // Local header carries zero sizes/CRC (flag bit 3); the real values follow the data.
        var zip = Data()
        zip.append(contentsOf: le32(0x0403_4B50) + le16(20) + le16(1 << 3) + le16(8) + le16(0) + le16(0x21))
        zip.append(contentsOf: le32(0) + le32(0) + le32(0) + le16(name.count) + le16(0) + name)
        zip.append(compressed)
        zip.append(contentsOf: le32(0x0807_4B50) + le32(crc) + le32(compressed.count) + le32(content.count))
        let directoryStart = zip.count
        zip.append(contentsOf: le32(0x0201_4B50) + le16(20) + le16(20) + le16(1 << 3) + le16(8) + le16(0) + le16(0x21))
        zip.append(contentsOf: le32(crc) + le32(compressed.count) + le32(content.count))
        zip.append(contentsOf: le16(name.count) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(0) + name)
        let directorySize = zip.count - directoryStart
        zip.append(contentsOf: le32(0x0605_4B50) + le16(0) + le16(0) + le16(1) + le16(1))
        zip.append(contentsOf: le32(directorySize) + le32(directoryStart) + le16(0))

        let reader = try ZipReader(data: zip)
        #expect(try reader.data(for: "d.txt") == content)
    }

    @Test func rejectsTooManyEntries() throws {
        let entries = (0...ZipReader.maxEntryCount).map { ZipEntry(path: "f\($0)", data: Data(), method: .stored) }
        let zip = try ZipWriter.archive(entries)
        #expect(throws: ImportError.self) { try ZipReader(data: zip) }
    }

    @Test func rejectsHugeDeclaredSizeAndLyingSizes() throws {
        let zip = try ZipWriter.archive([ZipEntry(path: "a.txt", data: Data(Self.text.utf8), method: .deflated)])
        let directoryStart = try #require(zip.range(of: Data(le32(0x0201_4B50)))).lowerBound
        let sizeField = directoryStart + 24

        var huge = zip
        huge.replaceSubrange(sizeField..<sizeField + 4, with: le32(ZipReader.maxUncompressedSize + 1))
        let hugeReader = try ZipReader(data: huge)
        #expect(throws: ImportError.self) { try hugeReader.data(for: "a.txt") }

        var lying = zip
        lying.replaceSubrange(sizeField..<sizeField + 4, with: le32(10))
        let lyingReader = try ZipReader(data: lying)
        #expect(throws: ImportError.self) { try lyingReader.data(for: "a.txt") }
    }

    @Test func totalDecompressedBudgetIsEnforced() throws {
        let zip = try ZipWriter.archive([
            ZipEntry(path: "a", data: Data(repeating: 1, count: 10), method: .stored),
            ZipEntry(path: "b", data: Data(repeating: 2, count: 10), method: .stored),
        ])
        let reader = try ZipReader(data: zip, totalBudget: 15)
        #expect(try reader.data(for: "a").count == 10)
        #expect(!reader.isBudgetExhausted)
        #expect(throws: ImportError.self) { try reader.data(for: "b") }
        #expect(reader.isBudgetExhausted)
    }
}
