import Foundation
import UniformTypeIdentifiers

/// Writes an EPUB 3 package with EPUB 2 fallbacks (toc.ncx, `meta name="cover"`)
/// for readers such as PocketBook. Output is deterministic for a given document and `modified` date.
public struct EPUBWriter: BookWriter {
    private let modified: Date

    public init(modified: Date = .now) {
        self.modified = modified
    }

    /// One XHTML file produced from a part or a leaf chapter, plus its table-of-contents node.
    private struct Node {
        var label: String
        var fileName: String
        var children: [Node]
    }

    private struct ChapterFile {
        var fileName: String
        var title: String
        var body: String
    }

    public func write(_ document: BookDocument, cover: ImageAsset?) throws -> Data {
        let metadata = document.metadata.normalizedForOutput
        let rtl = metadata.isRightToLeft
        let identifier = document.identifier.uuidString

        // Chapters
        var files: [ChapterFile] = []
        var tree: [Node] = []
        for chapter in document.chapters {
            tree.append(makeNode(chapter, depth: 0, bookTitle: metadata.title, files: &files))
        }

        var entries: [ZipEntry] = [
            ZipEntry(path: "mimetype", data: Data("application/epub+zip".utf8), method: .stored),
            ZipEntry(path: "META-INF/container.xml", data: utf8(EPUBTemplates.containerXML)),
        ]

        // Images
        var manifest: [String] = []
        var spine: [String] = []
        var imageEntries: [ZipEntry] = []

        manifest.append("<item id=\"ncx\" href=\"toc.ncx\" media-type=\"application/x-dtbncx+xml\"/>")
        manifest.append("<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>")
        manifest.append("<item id=\"css\" href=\"style.css\" media-type=\"text/css\"/>")

        if let cover {
            let ext = Self.fileExtension(for: cover)
            let path = "images/cover.\(ext)"
            manifest.append("<item id=\"cover-image\" href=\"\(path)\" media-type=\"\(Self.mediaType(for: cover))\" properties=\"cover-image\"/>")
            manifest.append("<item id=\"cover\" href=\"text/cover.xhtml\" media-type=\"application/xhtml+xml\"/>")
            spine.append("<itemref idref=\"cover\"/>")
            imageEntries.append(ZipEntry(path: "OEBPS/" + path, data: cover.data, method: .stored))
            let body = EPUBTemplates.coverBody(imagePath: "../" + path)
            entries.append(ZipEntry(
                path: "OEBPS/text/cover.xhtml",
                data: utf8(EPUBTemplates.xhtml(title: metadata.title, language: metadata.language, isRightToLeft: rtl, body: body))
            ))
        }

        for (index, file) in files.enumerated() {
            let id = "chapter-\(Self.padded(index + 1))"
            manifest.append("<item id=\"\(id)\" href=\"text/\(file.fileName)\" media-type=\"application/xhtml+xml\"/>")
            spine.append("<itemref idref=\"\(id)\"/>")
        }

        var seenImages = Set<String>()
        for asset in document.allImages where seenImages.insert(asset.id).inserted {
            let path = "images/\(Self.imageFileName(for: asset))"
            manifest.append("<item id=\"\(Self.imageManifestID(for: asset))\" href=\"\(path)\" media-type=\"\(Self.mediaType(for: asset))\"/>")
            imageEntries.append(ZipEntry(path: "OEBPS/" + path, data: asset.data, method: .stored))
        }

        // Package files
        let modifiedString = modified.formatted(.iso8601)
        entries.append(ZipEntry(path: "OEBPS/content.opf", data: utf8(EPUBTemplates.opf(
            identifier: identifier,
            metadata: metadata,
            modified: modifiedString,
            manifest: manifest,
            spine: spine,
            isRightToLeft: rtl,
            hasCover: cover != nil
        ))))
        entries.append(ZipEntry(path: "OEBPS/nav.xhtml", data: utf8(EPUBTemplates.nav(
            language: metadata.language,
            isRightToLeft: rtl,
            title: metadata.title,
            list: Self.navList(tree, indent: 0)
        ))))
        var playOrder = 0
        entries.append(ZipEntry(path: "OEBPS/toc.ncx", data: utf8(EPUBTemplates.ncx(
            identifier: identifier,
            title: metadata.title,
            depth: Self.depth(of: tree),
            navPoints: Self.navPoints(tree, indent: 2, playOrder: &playOrder)
        ))))
        entries.append(ZipEntry(path: "OEBPS/style.css", data: utf8(EPUBTemplates.stylesheet)))

        for file in files {
            entries.append(ZipEntry(path: "OEBPS/text/" + file.fileName, data: utf8(EPUBTemplates.xhtml(
                title: file.title, language: metadata.language, isRightToLeft: rtl, body: file.body
            ))))
        }
        entries.append(contentsOf: imageEntries)

        return try ZipWriter.archive(entries)
    }

    // MARK: - Chapters

    /// Emits the file for `chapter` (then for its children, depth-first) and returns its TOC node.
    private func makeNode(_ chapter: Chapter, depth: Int, bookTitle: String, files: inout [ChapterFile]) -> Node {
        let fileName = "chapter-\(Self.padded(files.count + 1)).xhtml"
        let title = chapter.title.flatMap { $0.isEmpty ? nil : $0 }
        let label = title ?? (files.isEmpty ? bookTitle : "\u{2026}")

        var body: [String] = []
        if let title {
            let tag = depth == 0 ? "h1" : "h2"
            body.append("<\(tag)>\(XMLEscaping.escape(title))</\(tag)>")
        }
        body.append(contentsOf: chapter.blocks.map(Self.markup(for:)))
        files.append(ChapterFile(fileName: fileName, title: label, body: body.joined(separator: "\n")))

        let children = chapter.children.map {
            makeNode($0, depth: depth + 1, bookTitle: bookTitle, files: &files)
        }
        return Node(label: label, fileName: fileName, children: children)
    }

    private static func markup(for block: Block) -> String {
        switch block {
        case .heading(let level, let runs):
            let tag = "h\(min(6, max(3, level + 2)))"
            return "<\(tag)>\(markup(for: runs))</\(tag)>"
        case .paragraph(let runs):
            return "<p>\(markup(for: runs))</p>"
        case .image(let asset):
            return "<div class=\"image\"><img src=\"../images/\(imageFileName(for: asset))\" alt=\"\"/></div>"
        }
    }

    private static func markup(for runs: [InlineRun]) -> String {
        runs.map { run in
            var text = XMLEscaping.escape(run.text)
            if run.isItalic { text = "<em>\(text)</em>" }
            if run.isBold { text = "<strong>\(text)</strong>" }
            return text
        }.joined()
    }

    // MARK: - Navigation

    private static func navList(_ nodes: [Node], indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        let items = nodes.map { node -> String in
            let link = "<a href=\"text/\(node.fileName)\">\(XMLEscaping.escape(node.label))</a>"
            if node.children.isEmpty {
                return "\(pad)  <li>\(link)</li>"
            }
            return "\(pad)  <li>\(link)\n\(navList(node.children, indent: indent + 2))\n\(pad)  </li>"
        }
        return "\(pad)<ol>\n\(items.joined(separator: "\n"))\n\(pad)</ol>"
    }

    private static func navPoints(_ nodes: [Node], indent: Int, playOrder: inout Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        var result: [String] = []
        for node in nodes {
            playOrder += 1
            let order = playOrder
            var point = """
            \(pad)<navPoint id="navpoint-\(order)" playOrder="\(order)">
            \(pad)  <navLabel><text>\(XMLEscaping.escape(node.label))</text></navLabel>
            \(pad)  <content src="text/\(node.fileName)"/>
            """
            if !node.children.isEmpty {
                point += "\n" + navPoints(node.children, indent: indent + 1, playOrder: &playOrder)
            }
            point += "\n\(pad)</navPoint>"
            result.append(point)
        }
        return result.joined(separator: "\n")
    }

    private static func depth(of nodes: [Node]) -> Int {
        (nodes.map { 1 + depth(of: $0.children) }.max()) ?? 1
    }

    // MARK: - Helpers

    private func utf8(_ string: String) -> Data { Data(string.utf8) }

    private static func padded(_ number: Int) -> String {
        let digits = String(number)
        return String(repeating: "0", count: max(0, 3 - digits.count)) + digits
    }

    private static func fileExtension(for asset: ImageAsset) -> String {
        asset.contentType.conforms(to: .png) ? "png" : "jpg"
    }

    private static func mediaType(for asset: ImageAsset) -> String {
        asset.contentType.conforms(to: .png) ? "image/png" : "image/jpeg"
    }

    /// Asset ids are restricted to filename- and XML-id-safe characters.
    private static func safeID(_ id: String) -> String {
        let mapped = id.unicodeScalars.map { scalar -> Character in
            let isSafe = scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(Character(scalar)) || scalar == "-" || scalar == "_")
            return isSafe ? Character(scalar) : "_"
        }
        return String(mapped)
    }

    private static func imageFileName(for asset: ImageAsset) -> String {
        "\(safeID(asset.id)).\(fileExtension(for: asset))"
    }

    private static func imageManifestID(for asset: ImageAsset) -> String {
        "img-\(safeID(asset.id))"
    }
}
