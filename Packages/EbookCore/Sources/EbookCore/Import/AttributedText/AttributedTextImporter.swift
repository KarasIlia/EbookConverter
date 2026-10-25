import AppKit

/// Imports RTF, DOC, DOCX and HTML through `NSAttributedString`.
///
/// The real format is detected from content, not the extension (an RTF named `.doc` imports as RTF).
/// HTML images are resolved by this importer, never fetched by WebKit.
public struct AttributedTextImporter: BookImporter {
    private static let htmlExtensions: Set<String> = ["html", "htm", "xhtml"]
    /// Bytes scanned for an HTML `charset` declaration.
    private static let charsetScanLength = 4096

    public init() {}

    public func importBook(from url: URL, context: ImportContext) async throws -> ImportResult {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw ImportError.unreadable(error.localizedDescription) }
        let isRTF = data.starts(with: Data(#"{\rtf"#.utf8))
        let loaded: Loaded
        if !isRTF, Self.looksLikeHTML(data, url: url) {
            loaded = try await importHTML(data, url: url, context: context)
        } else {
            loaded = try await MainActor.run { try Self.load(url: url, isRTF: isRTF) }
        }

        var items = loaded.items
        var imageNumber = 0
        for (index, item) in items.enumerated() {
            guard case .image(let asset) = item else { continue }
            imageNumber += 1
            items[index] = .image(ImageAsset(
                id: "img-\(imageNumber)", data: asset.data, contentType: asset.contentType,
                pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight
            ))
        }

        let built = StructureBuilder.build(items)
        guard !built.chapters.isEmpty else { throw ImportError.emptyDocument }

        var warnings = loaded.warnings
        let plainText = items.compactMap { item -> String? in
            if case .paragraph(let paragraph) = item { paragraph.text } else { nil }
        }.joined(separator: "\n")
        let language = LanguageDetector.language(of: plainText)
        if language == nil { warnings.append(.languageUndetermined) }
        if !built.foundHeadings { warnings.append(.noChaptersFound) }

        // RTF \info is re-read from the raw bytes; NSAttributedString may decode it with the wrong codepage.
        let rtfInfo = isRTF ? RTFInfoDecoder.metadata(fromRTF: data) : (title: nil, author: nil)
        let fallbackTitle = url.deletingPathExtension().lastPathComponent.replacing("_", with: " ")
        let metadata = BookMetadata(
            title: rtfInfo.title ?? Self.nonEmpty(loaded.title) ?? fallbackTitle,
            author: rtfInfo.author ?? Self.nonEmpty(loaded.author) ?? "",
            language: language ?? "und"
        )
        return ImportResult(document: BookDocument(metadata: metadata, chapters: built.chapters), warnings: warnings)
    }

    // MARK: - Loading

    /// What one `NSAttributedString` load produced.
    private struct Loaded: Sendable {
        var items: [StructuredItem]
        var warnings: [ImportWarning]
        var title: String?
        var author: String?
    }

    @MainActor
    private static func load(url: URL, isRTF: Bool) throws -> Loaded {
        var attributes: NSDictionary?
        let string: NSAttributedString
        // RTF is forced so an RTF named `.doc` is never handed to the Word reader.
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = isRTF ? [.documentType: NSAttributedString.DocumentType.rtf] : [:]
        do {
            string = try NSAttributedString(url: url, options: options, documentAttributes: &attributes)
        } catch {
            throw ImportError.unreadable(error.localizedDescription)
        }
        // DOC/DOCX images often come back as a bare U+FFFC without data (accepted limitation).
        var lost = 0
        var imageCount = 0
        let items = AttributedStringFlattener.items(from: string) { _, attachment in
            guard let attachment, let asset = AttributedStringFlattener.imageAsset(of: attachment, id: "img-\(imageCount + 1)") else {
                lost += 1
                return nil
            }
            imageCount += 1
            return asset
        }
        return Loaded(
            items: items,
            warnings: lost > 0 ? [.imagesUnavailable(count: lost)] : [],
            title: attributes?[NSAttributedString.DocumentAttributeKey.title] as? String,
            author: attributes?[NSAttributedString.DocumentAttributeKey.author] as? String
        )
    }

    // MARK: - HTML

    private func importHTML(_ data: Data, url: URL, context: ImportContext) async throws -> Loaded {
        guard let source = Self.decodeHTML(data) else { throw ImportError.unreadable("Unrecognized text encoding") }
        let (html, references) = HTMLSubresourceNeutralizer.neutralize(source)
        let outcomes = references.enumerated().map { index, reference in
            HTMLImageResolver.loadLocalImage(
                reference: reference, relativeTo: url, accessibleFolder: context.accessibleFolder, id: "img-\(index + 1)"
            )
        }

        let (parsed, placed) = try await MainActor.run {
            var attributes: NSDictionary?
            let string: NSAttributedString
            do {
                string = try NSAttributedString(
                    data: Data(html.utf8),
                    options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                    documentAttributes: &attributes
                )
            } catch {
                throw ImportError.unreadable(error.localizedDescription)
            }
            // The n-th attachment is the n-th neutralized <img>; anything beyond that has no source to load.
            var placed = 0
            let items = AttributedStringFlattener.items(from: string) { index, _ in
                placed = max(placed, index + 1)
                guard index < outcomes.count, case .loaded(let asset) = outcomes[index] else { return nil }
                return asset
            }
            let parsed = Loaded(
                items: items,
                warnings: [],
                title: attributes?[NSAttributedString.DocumentAttributeKey.title] as? String,
                author: attributes?[NSAttributedString.DocumentAttributeKey.author] as? String
            )
            return (parsed, placed)
        }

        var loaded = parsed
        if Self.nonEmpty(loaded.title) == nil { loaded.title = Self.titleElement(in: source) }
        var needsFolderAccess = false
        var remote = 0
        var missing = max(placed - outcomes.count, 0)
        for (index, outcome) in outcomes.enumerated() {
            switch outcome {
            case .loaded: if index >= placed { missing += 1 }
            case .needsFolderAccess: needsFolderAccess = true
            case .remote: remote += 1
            case .missing: missing += 1
            }
        }
        if needsFolderAccess { loaded.warnings.append(.imagesNeedFolderAccess(folder: url.deletingLastPathComponent())) }
        if remote > 0 { loaded.warnings.append(.remoteImagesSkipped(count: remote)) }
        if missing > 0 { loaded.warnings.append(.imagesUnavailable(count: missing)) }
        return loaded
    }

    private static func looksLikeHTML(_ data: Data, url: URL) -> Bool {
        if htmlExtensions.contains(url.pathExtension.lowercased()) { return true }
        let head = String(decoding: data.prefix(1024), as: UTF8.self).lowercased()
        return head.contains("<!doctype html") || head.contains("<html")
    }

    /// Decodes with the `charset` the page declares, else by detection.
    private static func decodeHTML(_ data: Data) -> String? {
        let head = String(decoding: data.prefix(charsetScanLength), as: UTF8.self)
        if let match = head.firstMatch(of: /(?i)charset\s*=\s*["']?([A-Za-z0-9_\-:.]+)/) {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(String(match.output.1) as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
                if let text = String(data: data, encoding: encoding) { return text }
            }
        }
        return TextEncodingDetector.decode(data)
    }

    /// Text of the page's `<title>`, entity-decoded with whitespace collapsed; WebKit does not report it.
    private static func titleElement(in html: String) -> String? {
        guard let match = html.firstMatch(of: /(?is)<title\b[^>]*>(.*?)<\/title\s*>/) else { return nil }
        let text = HTMLSubresourceNeutralizer.decodeEntities(String(match.output.1))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
