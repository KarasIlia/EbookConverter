import Foundation

/// Detects the source format from file content first; the file extension only separates Markdown from plain text.
public enum FormatSniffer {
    private static let textProbeLength = 8 * 1024
    private static let markupProbeLength = 1024
    private static let compoundFileSignature: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
    private static let zipSignature: [UInt8] = [0x50, 0x4B, 0x03, 0x04]

    public static func format(of data: Data, fileExtension: String) -> SourceFormat? {
        guard !data.isEmpty else { return nil }
        let head = [UInt8](data.prefix(8))
        if head.starts(with: Array("%PDF".utf8)) { return .pdf }
        if head.starts(with: zipSignature) { return zipFormat(data) }
        if head.starts(with: Array("{\\rtf".utf8)) { return .rtf }
        if head.starts(with: compoundFileSignature) { return .doc }

        guard isText(data) else { return nil }
        let markup = markupHead(of: data)
        let lowercasedExtension = fileExtension.lowercased()
        let isMarkdown = lowercasedExtension == "md" || lowercasedExtension == "markdown"

        if markup.hasPrefix("<?xml"), markup.contains("<fictionbook") { return .fb2 }
        // Plain-text and Markdown files may merely mention HTML tags, so they must start with the markup.
        let mayMentionHTML = isMarkdown || lowercasedExtension == "txt"
        let htmlMarkers = ["<!doctype html", "<html"]
        let isHTML = htmlMarkers.contains { mayMentionHTML ? markup.hasPrefix($0) : markup.contains($0) }
        if isHTML { return .html }

        guard TextEncodingDetector.decode(data) != nil else { return nil }
        return isMarkdown ? .markdown : .txt
    }

    /// EPUB and DOCX are ZIP archives; anything else (including FB2 inside a ZIP) is unsupported.
    private static func zipFormat(_ data: Data) -> SourceFormat? {
        guard let archive = try? ZipReader(data: data) else { return nil }
        if archive.paths.contains("mimetype"),
           let mimetype = try? archive.data(for: "mimetype"),
           String(decoding: mimetype, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "application/epub+zip" {
            return .epub
        }
        if archive.paths.contains("word/document.xml") { return .docx }
        return nil
    }

    /// Text has no NUL bytes in its first 8 KiB, unless it starts with a UTF-16/UTF-32 byte-order mark.
    private static func isText(_ data: Data) -> Bool {
        let head = [UInt8](data.prefix(4))
        let hasWideBOM = head.starts(with: [0xFF, 0xFE]) || head.starts(with: [0xFE, 0xFF])
            || head.starts(with: [0x00, 0x00, 0xFE, 0xFF])
        if hasWideBOM { return true }
        return !data.prefix(textProbeLength).contains(0)
    }

    /// The first KiB as lowercase text without a UTF-8 BOM and leading whitespace.
    private static func markupHead(of data: Data) -> String {
        var bytes = data.prefix(markupProbeLength)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        return String(decoding: bytes, as: UTF8.self)
            .lowercased()
            .drop { $0.isWhitespace }
            .description
    }
}
