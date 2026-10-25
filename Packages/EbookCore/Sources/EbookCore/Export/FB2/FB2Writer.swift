import Foundation
import UniformTypeIdentifiers

/// Writes a FictionBook 2 document. Output is deterministic for a given document and `date`.
public struct FB2Writer: BookWriter {
    private let date: Date

    public init(date: Date = .now) {
        self.date = date
    }

    public func write(_ document: BookDocument, cover: ImageAsset?) throws -> Data {
        let metadata = document.metadata
        var binaries = BinaryRegistry()
        let coverName = cover.map { binaries.register($0, preferredStem: "cover") }

        var body: [String] = []
        for chapter in document.chapters {
            body.append(Self.section(chapter, binaries: &binaries))
        }

        var out: [String] = []
        out.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        out.append("<FictionBook xmlns=\"http://www.gribuser.ru/xml/fictionbook/2.0\" xmlns:l=\"http://www.w3.org/1999/xlink\">")
        out.append("<description>")
        out.append("<title-info>")
        out.append("<genre>prose</genre>")
        out.append(Self.authorMarkup(metadata.author))
        out.append("<book-title>\(XMLEscaping.escape(metadata.title))</book-title>")
        if let coverName {
            out.append("<coverpage><image l:href=\"#\(XMLEscaping.escape(coverName))\"/></coverpage>")
        }
        out.append("<lang>\(XMLEscaping.escape(metadata.language))</lang>")
        out.append("</title-info>")
        out.append("<document-info>")
        out.append("<author><nickname>EbookConverter</nickname></author>")
        let day = date.formatted(Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day())
        out.append("<date value=\"\(day)\">\(day)</date>")
        out.append("<id>\(XMLEscaping.escape(document.identifier.uuidString))</id>")
        out.append("<version>1.0</version>")
        out.append("</document-info>")
        out.append("</description>")
        out.append("<body>")
        out.append(contentsOf: body)
        out.append("</body>")
        for binary in binaries.entries {
            let encoded = binary.asset.data.base64EncodedString(options: .lineLength76Characters)
            out.append("<binary id=\"\(XMLEscaping.escape(binary.name))\" content-type=\"\(Self.mediaType(for: binary.asset))\">\(encoded)</binary>")
        }
        out.append("</FictionBook>")
        return Data((out.joined(separator: "\n") + "\n").utf8)
    }

    // MARK: - Metadata

    private static func authorMarkup(_ author: String) -> String {
        let words = author.split(whereSeparator: \.isWhitespace).map(String.init)
        switch words.count {
        case 0:
            return "<author><nickname>Unknown</nickname></author>"
        case 1:
            return "<author><nickname>\(XMLEscaping.escape(words[0]))</nickname></author>"
        default:
            var parts = ["<first-name>\(XMLEscaping.escape(words[0]))</first-name>"]
            let middle = words.dropFirst().dropLast()
            if !middle.isEmpty {
                parts.append("<middle-name>\(XMLEscaping.escape(middle.joined(separator: " ")))</middle-name>")
            }
            parts.append("<last-name>\(XMLEscaping.escape(words[words.count - 1]))</last-name>")
            return "<author>\(parts.joined())</author>"
        }
    }

    // MARK: - Sections

    /// FB2 forbids mixing content and child sections, so a part's own blocks go into a leading untitled section.
    private static func section(_ chapter: Chapter, binaries: inout BinaryRegistry) -> String {
        var lines: [String] = ["<section>"]
        if let title = chapter.title, !title.isEmpty {
            lines.append("<title><p>\(XMLEscaping.escape(title))</p></title>")
        }
        let own = chapter.blocks.map { markup(for: $0, binaries: &binaries) }
        if chapter.children.isEmpty {
            // A section must not be empty.
            lines.append(contentsOf: own.isEmpty ? ["<empty-line/>"] : own)
        } else {
            if !own.isEmpty {
                lines.append("<section>")
                lines.append(contentsOf: own)
                lines.append("</section>")
            }
            for child in chapter.children {
                lines.append(section(child, binaries: &binaries))
            }
        }
        lines.append("</section>")
        return lines.joined(separator: "\n")
    }

    private static func markup(for block: Block, binaries: inout BinaryRegistry) -> String {
        switch block {
        case .heading(_, let runs):
            let inner = markup(for: runs)
            return inner.isEmpty ? "<empty-line/>" : "<subtitle>\(inner)</subtitle>"
        case .paragraph(let runs):
            let inner = markup(for: runs)
            return inner.isEmpty ? "<empty-line/>" : "<p>\(inner)</p>"
        case .image(let asset):
            let name = binaries.register(asset)
            return "<image l:href=\"#\(XMLEscaping.escape(name))\"/>"
        }
    }

    private static func markup(for runs: [InlineRun]) -> String {
        runs.filter { !$0.text.isEmpty }.map { run in
            var text = XMLEscaping.escape(run.text)
            if run.isItalic { text = "<emphasis>\(text)</emphasis>" }
            if run.isBold { text = "<strong>\(text)</strong>" }
            return text
        }.joined()
    }

    // MARK: - Binaries

    private static func mediaType(for asset: ImageAsset) -> String {
        asset.contentType.conforms(to: .png) ? "image/png" : "image/jpeg"
    }

    /// Assigns unique, XML-id-safe binary names; the same asset id always maps to the same name.
    private struct BinaryRegistry {
        struct Entry {
            var name: String
            var asset: ImageAsset
        }

        private(set) var entries: [Entry] = []
        private var namesByAssetKey: [String: String] = [:]
        private var usedNames = Set<String>()

        mutating func register(_ asset: ImageAsset, preferredStem: String? = nil) -> String {
            let key = (preferredStem.map { "\u{0}" + $0 } ?? "") + asset.id
            if let existing = namesByAssetKey[key] { return existing }
            let ext = asset.contentType.conforms(to: .png) ? "png" : "jpg"
            let stem = preferredStem ?? Self.safeID(asset.id)
            var name = "\(stem).\(ext)"
            var counter = 2
            while !usedNames.insert(name).inserted {
                name = "\(stem)_\(counter).\(ext)"
                counter += 1
            }
            namesByAssetKey[key] = name
            entries.append(Entry(name: name, asset: asset))
            return name
        }

        private static func safeID(_ id: String) -> String {
            let mapped = id.unicodeScalars.map { scalar -> Character in
                let isSafe = scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(Character(scalar)) || scalar == "-" || scalar == "_")
                return isSafe ? Character(scalar) : "_"
            }
            let result = String(mapped)
            return result.isEmpty ? "image" : result
        }
    }
}
