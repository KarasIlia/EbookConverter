import Foundation
import Testing
@testable import EbookCore

@Suite struct ZipWriterTests {
    @Test func crcKnownVectors() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF43926)
        #expect(CRC32.checksum(Data("The quick brown fox jumps over the lazy dog".utf8)) == 0x414FA339)
        #expect(CRC32.checksum(Data()) == 0)
    }

    @Test func firstEntryIsStoredMimetype() throws {
        let zip = try ZipWriter.archive(sampleEntries())
        #expect(Array(zip[0..<4]) == [0x50, 0x4B, 0x03, 0x04])
        #expect(String(decoding: zip[30..<38], as: UTF8.self) == "mimetype")
        #expect(String(decoding: zip[38..<58], as: UTF8.self) == "application/epub+zip")
    }

    @Test func unzipAcceptsArchive() throws {
        let zip = try ZipWriter.archive(sampleEntries())
        let url = URL.temporaryDirectory.appending(path: "ziptest-\(UUID().uuidString).zip")
        try zip.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let test = try run("/usr/bin/unzip", ["-t", url.path(percentEncoded: false)])
        #expect(test.status == 0)
        let extracted = try run("/usr/bin/unzip", ["-p", url.path(percentEncoded: false), "a.txt"])
        #expect(extracted.status == 0)
        #expect(extracted.output == Self.text)
    }

    @Test func deterministicOutput() throws {
        #expect(try ZipWriter.archive(sampleEntries()) == ZipWriter.archive(sampleEntries()))
    }

    static let text = String(repeating: "Привет, мир! ", count: 50)

    private func sampleEntries() -> [ZipEntry] {
        [
            ZipEntry(path: "mimetype", data: Data("application/epub+zip".utf8), method: .stored),
            ZipEntry(path: "a.txt", data: Data(Self.text.utf8), method: .deflated),
        ]
    }

    private func run(_ tool: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
