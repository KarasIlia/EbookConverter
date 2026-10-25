import Foundation
import PDFKit

/// Imports the text layer of a PDF: lines are reflowed into paragraphs, chapters come from the
/// document outline when it has one, otherwise from heading detection.
public struct PDFImporter: BookImporter {
    /// Below this many extracted characters per page the PDF is treated as scanned images.
    static let minimumCharactersPerPage = 20
    /// Slack when deciding whether a paragraph starts at or below an outline destination.
    static let destinationTolerance = 2.0

    public init() {}

    public func importBook(from url: URL, context: ImportContext) async throws -> ImportResult {
        guard let document = PDFDocument(url: url) else { throw ImportError.unreadable("Not a readable PDF") }
        guard !document.isLocked else { throw ImportError.pdfLocked }

        let lines = PDFLineExtractor.lines(in: document)
        let characterCount = lines.reduce(0) { $0 + $1.text.count }
        guard characterCount >= Self.minimumCharactersPerPage * max(document.pageCount, 1) else {
            throw ImportError.pdfHasNoTextLayer
        }
        let located = PDFReflow.locatedParagraphs(from: PDFReflow.removingRunningHeaders(lines))
        guard !located.isEmpty else { throw ImportError.emptyDocument }

        let chapters: [Chapter]
        let foundHeadings: Bool
        if let outline = Self.outlineMarkers(of: document) {
            chapters = Self.chapters(from: located, markers: outline)
            foundHeadings = true
        } else {
            (chapters, foundHeadings) = StructureBuilder.build(located.map { .paragraph($0.paragraph) })
        }
        guard !chapters.isEmpty else { throw ImportError.emptyDocument }

        var warnings: [ImportWarning] = []
        let language = LanguageDetector.language(of: located.map(\.paragraph.text).joined(separator: "\n"))
        if language == nil { warnings.append(.languageUndetermined) }
        if !foundHeadings { warnings.append(.noChaptersFound) }

        let attributes = document.documentAttributes ?? [:]
        let fallbackTitle = url.deletingPathExtension().lastPathComponent.replacing("_", with: " ")
        let metadata = BookMetadata(
            title: Self.attribute(PDFDocumentAttribute.titleAttribute, in: attributes) ?? fallbackTitle,
            author: Self.attribute(PDFDocumentAttribute.authorAttribute, in: attributes) ?? "",
            language: language ?? "und"
        )
        return ImportResult(document: BookDocument(metadata: metadata, chapters: chapters), warnings: warnings)
    }

    private static func attribute(_ key: PDFDocumentAttribute, in attributes: [AnyHashable: Any]) -> String? {
        guard let value = attributes[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Outline

    /// One outline entry flattened to the book's two TOC levels.
    private struct Marker {
        var title: String
        /// `true` for an entry nested inside a part (the closest preceding top-level marker).
        var isInPart: Bool
        /// Destination page index and y in visible page space; `nil` when the entry points nowhere.
        var page: Int?
        var y: Double
    }

    /// Top-level entries become parts if they have children, otherwise chapters; deeper levels are flattened
    /// into their part's chapters. `nil` when there is no usable outline.
    private static func outlineMarkers(of document: PDFDocument) -> [Marker]? {
        guard let root = document.outlineRoot, root.numberOfChildren > 0 else { return nil }
        var markers: [Marker] = []

        func marker(for entry: PDFOutline, isInPart: Bool) -> Marker {
            let destination = entry.destination ?? (entry.action as? PDFActionGoTo)?.destination
            var marker = Marker(
                title: (entry.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                isInPart: isInPart, page: nil, y: 0
            )
            if let destination, let page = destination.page {
                let index = document.index(for: page)
                if index != NSNotFound {
                    marker.page = index
                    marker.y = PDFLineExtractor.visiblePoint(destination.point, on: page).y
                }
            }
            return marker
        }

        func appendDescendants(of entry: PDFOutline) {
            for index in 0..<entry.numberOfChildren {
                guard let child = entry.child(at: index) else { continue }
                markers.append(marker(for: child, isInPart: true))
                appendDescendants(of: child)
            }
        }

        for index in 0..<root.numberOfChildren {
            guard let entry = root.child(at: index) else { continue }
            markers.append(marker(for: entry, isInPart: false))
            appendDescendants(of: entry)
        }
        return markers.contains { $0.page != nil } ? markers : nil
    }

    /// Splits the paragraph stream at each marker's destination, in reading order.
    private static func chapters(from located: [PDFReflow.Located], markers: [Marker]) -> [Chapter] {
        var starts: [Int] = []
        for marker in markers {
            let previous = starts.last ?? 0
            guard let page = marker.page else {
                starts.append(previous)
                continue
            }
            let start = located.firstIndex { item in
                let line = item.firstLine
                return line.pageIndex > page
                    || (line.pageIndex == page && line.bounds.maxY <= marker.y + destinationTolerance)
            } ?? located.count
            starts.append(max(start, previous))
        }

        var chapters: [Chapter] = []
        if let first = starts.first, first > 0 {
            chapters.append(Chapter(blocks: located[0..<first].map { .paragraph($0.paragraph.runs) }))
        }
        for (index, marker) in markers.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1] : located.count
            var range = located[starts[index]..<end]
            // The heading line that repeats the outline label is already the chapter title.
            if let first = range.first, normalizedTitle(first.paragraph.text) == normalizedTitle(marker.title) {
                range = range.dropFirst()
            }
            let chapter = Chapter(
                title: marker.title.isEmpty ? nil : marker.title,
                blocks: range.map { .paragraph($0.paragraph.runs) }
            )
            if marker.isInPart, var part = chapters.popLast() {
                part.children.append(chapter)
                chapters.append(part)
            } else {
                chapters.append(chapter)
            }
        }
        return chapters
    }

    private static func normalizedTitle(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
}
