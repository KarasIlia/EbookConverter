import Foundation

/// Imports FictionBook 2 files (`.fb2`; `.fb2.zip` is not supported).
///
/// Reads the first `body` that is not a notes body. Top-level sections become chapters, their sections
/// become sub-chapters, and anything deeper is flattened into the sub-chapter with its title as a level-3 heading.
public struct FB2Importer: BookImporter {
    public init() {}

    public func importBook(from url: URL, context: ImportContext) async throws -> ImportResult {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw ImportError.unreadable(error.localizedDescription) }
        let fallbackTitle = url.deletingPathExtension().lastPathComponent.replacing("_", with: " ")
        return try Self.makeResult(from: data, fallbackTitle: fallbackTitle)
    }

    private static func makeResult(from data: Data, fallbackTitle: String) throws -> ImportResult {
        let parsed = XMLTreeNode.parseReportingTruncation(data)
        guard let root = parsed.root, root.name == "fictionbook" else {
            throw ImportError.unreadable("Not an FB2 document")
        }

        let images = FB2ImageResolver(binaries: root.children(named: "binary"))
        let body = root.children(named: "body").first { $0.attributes["name"]?.lowercased() != "notes" }
        let converter = FB2BodyConverter(images: images)
        var chapters = body.map(converter.chapters(in:)) ?? []
        chapters = EmptyChapterPruner.pruned(chapters)
        guard !chapters.isEmpty else { throw ImportError.emptyDocument }

        var warnings: [ImportWarning] = []
        if images.missingCount > 0 { warnings.append(.imagesUnavailable(count: images.missingCount)) }
        if parsed.isTruncated { warnings.append(.contentPartiallyUnreadable(count: 1)) }

        let titleInfo = root.firstChild(named: "description")?.firstChild(named: "title-info")
        var language = titleInfo?.firstChild(named: "lang")?.collapsedText
        if language?.isEmpty ?? true {
            language = LanguageDetector.language(of: allText(of: chapters))
        }
        if language == nil { warnings.append(.languageUndetermined) }
        if !hasTitle(chapters) { warnings.append(.noChaptersFound) }

        let title = titleInfo?.firstChild(named: "book-title")?.collapsedText
        let metadata = BookMetadata(
            title: title.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle,
            author: (titleInfo?.children(named: "author").compactMap(authorName) ?? []).joined(separator: ", "),
            language: language ?? "und"
        )
        let cover = titleInfo?.firstChild(named: "coverpage")
            .flatMap { $0.firstDescendant { $0.name == "image" } }
            .flatMap { images.cover(for: $0) }
        return ImportResult(
            document: BookDocument(metadata: metadata, chapters: chapters), sourceCover: cover, warnings: warnings
        )
    }

    // MARK: - Metadata

    private static func authorName(_ author: XMLTreeNode) -> String? {
        let parts = ["first-name", "middle-name", "last-name"]
            .compactMap { author.firstChild(named: $0)?.collapsedText }
            .filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        let nickname = author.firstChild(named: "nickname")?.collapsedText
        return nickname.flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Chapter helpers

    private static func hasTitle(_ chapters: [Chapter]) -> Bool {
        chapters.contains { $0.title != nil || hasTitle($0.children) }
    }

    private static func allText(of chapters: [Chapter]) -> String {
        chapters.map { ([$0.plainText] + [allText(of: $0.children)]).joined(separator: "\n") }.joined(separator: "\n")
    }
}
