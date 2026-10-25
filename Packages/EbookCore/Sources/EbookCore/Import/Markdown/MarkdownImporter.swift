import Foundation

/// Imports Markdown books, including images referenced by relative path.
public struct MarkdownImporter: BookImporter {
    public init() {}

    public func importBook(from url: URL, context: ImportContext) async throws -> ImportResult {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw ImportError.unreadable(error.localizedDescription) }
        guard let text = TextEncodingDetector.decode(data) else {
            throw ImportError.unreadable("Unrecognized text encoding")
        }
        let parsed: AttributedString
        do {
            parsed = try AttributedString(markdown: text, options: .init(interpretedSyntax: .full))
        } catch {
            throw ImportError.unreadable(error.localizedDescription)
        }

        var collector = Collector(fileURL: url, accessibleFolder: context.accessibleFolder)
        collector.collect(parsed)
        var items = collector.items

        // A lone "#" heading at the very top names the book instead of starting a part.
        var title: String?
        let topLevelCount = items.count { item in
            if case .paragraph(let paragraph) = item { paragraph.headingLevelHint == 1 } else { false }
        }
        if topLevelCount == 1, case .paragraph(let first) = items.first, first.headingLevelHint == 1 {
            title = first.text.trimmingCharacters(in: .whitespacesAndNewlines)
            items.removeFirst()
        }

        let built = StructureBuilder.build(items)
        guard !built.chapters.isEmpty else { throw ImportError.emptyDocument }

        var warnings: [ImportWarning] = []
        if collector.needsFolderAccess {
            warnings.append(.imagesNeedFolderAccess(folder: url.deletingLastPathComponent()))
        }
        if collector.remoteCount > 0 { warnings.append(.remoteImagesSkipped(count: collector.remoteCount)) }
        if collector.missingCount > 0 { warnings.append(.imagesUnavailable(count: collector.missingCount)) }

        let plainText = items.compactMap { item -> String? in
            if case .paragraph(let paragraph) = item { paragraph.text } else { nil }
        }.joined(separator: "\n")
        let language = LanguageDetector.language(of: plainText)
        if language == nil { warnings.append(.languageUndetermined) }
        if !built.foundHeadings { warnings.append(.noChaptersFound) }

        let fallbackTitle = url.deletingPathExtension().lastPathComponent.replacing("_", with: " ")
        let metadata = BookMetadata(
            title: title.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle,
            author: "",
            language: language ?? "und"
        )
        return ImportResult(document: BookDocument(metadata: metadata, chapters: built.chapters), warnings: warnings)
    }
}

// MARK: - Run collection

/// Walks the parsed runs, grouping them into paragraphs by block identity and loading images.
private struct Collector {
    let fileURL: URL
    let accessibleFolder: URL?

    private(set) var items: [StructuredItem] = []
    private(set) var needsFolderAccess = false
    private(set) var remoteCount = 0
    private(set) var missingCount = 0

    private var imageCount = 0
    private var currentBlock: Int?
    private var currentHint: Int?
    private var currentRuns: [InlineRun] = []

    init(fileURL: URL, accessibleFolder: URL?) {
        self.fileURL = fileURL
        self.accessibleFolder = accessibleFolder
    }

    mutating func collect(_ text: AttributedString) {
        var lastBlock: Int?
        var started = false
        for run in text.runs {
            let components = run.presentationIntent?.components ?? []
            let block = components.first?.identity
            if !started || block != lastBlock {
                flush()
                started = true
                lastBlock = block
                currentHint = Self.headingLevel(of: components)
                if let marker = Self.listMarker(of: components) { currentRuns.append(InlineRun(marker)) }
            }
            if let reference = run.imageURL?.relativeString {
                flush()
                addImage(reference: reference)
                continue
            }
            let intent = run.inlinePresentationIntent ?? []
            var piece = String(text[run.range].characters)
            if intent.contains(.lineBreak) { piece = " " }
            append(InlineRun(
                piece,
                bold: intent.contains(.stronglyEmphasized),
                italic: intent.contains(.emphasized)
            ))
        }
        flush()
    }

    private mutating func append(_ run: InlineRun) {
        if var last = currentRuns.last, last.isBold == run.isBold, last.isItalic == run.isItalic {
            last.text += run.text
            currentRuns[currentRuns.count - 1] = last
        } else {
            currentRuns.append(run)
        }
    }

    private mutating func flush() {
        defer { currentRuns = [] }
        let hasText = currentRuns.contains { !$0.text.allSatisfy(\.isWhitespace) }
        guard hasText else { return }
        items.append(.paragraph(StyledParagraph(runs: currentRuns, headingLevelHint: currentHint)))
    }

    private mutating func addImage(reference: String) {
        let outcome = HTMLImageResolver.loadLocalImage(
            reference: reference, relativeTo: fileURL, accessibleFolder: accessibleFolder,
            id: "img-\(imageCount + 1)"
        )
        switch outcome {
        case .loaded(let asset):
            imageCount += 1
            items.append(.image(asset))
        case .needsFolderAccess: needsFolderAccess = true
        case .remote: remoteCount += 1
        case .missing: missingCount += 1
        }
    }

    /// `#` is level 1, `##` level 2, anything deeper level 3.
    private static func headingLevel(of components: [PresentationIntent.IntentType]) -> Int? {
        for component in components {
            if case .header(let level) = component.kind { return min(max(level, 1), 3) }
        }
        return nil
    }

    private static func listMarker(of components: [PresentationIntent.IntentType]) -> String? {
        var ordinal: Int?
        for component in components {
            switch component.kind {
            case .listItem(let value): ordinal = value
            case .orderedList: return ordinal.map { "\($0). " }
            case .unorderedList: return "• "
            default: break
            }
        }
        return nil
    }
}
