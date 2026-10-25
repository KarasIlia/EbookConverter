import Foundation

/// Imports plain-text books in any common encoding.
public struct TXTImporter: BookImporter {
    /// Longest all-capitals line still treated as a heading.
    private static let maxCapitalsHeadingLength = 60

    /// If more than this share of paragraphs look like ALL-CAPS headings, none is treated as one.
    private static let maxCapitalsShare = 0.2

    public init() {}

    public func importBook(from url: URL, context: ImportContext) async throws -> ImportResult {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw ImportError.unreadable(error.localizedDescription) }
        guard let decoded = TextEncodingDetector.decode(data) else {
            throw ImportError.unreadable("Unrecognized text encoding")
        }
        let paragraphs = Self.paragraphs(in: decoded)
        guard !paragraphs.isEmpty else { throw ImportError.emptyDocument }

        // Plays and scripts have many ALL-CAPS speaker names; those are not headings.
        let capitals = paragraphs.map(Self.isCapitalsHeading)
        let capitalsShare = Double(capitals.count { $0 }) / Double(paragraphs.count)
        let useCapitalsHints = capitalsShare <= Self.maxCapitalsShare
        let items = zip(paragraphs, capitals).map { paragraph, isCapitals in
            StructuredItem.paragraph(StyledParagraph(
                runs: [InlineRun(paragraph)],
                headingLevelHint: useCapitalsHints && isCapitals ? 2 : nil
            ))
        }
        let built = StructureBuilder.build(items)

        var warnings: [ImportWarning] = []
        let language = LanguageDetector.language(of: paragraphs.joined(separator: "\n"))
        if language == nil { warnings.append(.languageUndetermined) }
        if !built.foundHeadings { warnings.append(.noChaptersFound) }

        let title = url.deletingPathExtension().lastPathComponent.replacing("_", with: " ")
        let metadata = BookMetadata(title: title, author: "", language: language ?? "und")
        return ImportResult(
            document: BookDocument(metadata: metadata, chapters: built.chapters),
            warnings: warnings
        )
    }

    /// Splits on blank lines; a file without blank lines yields one paragraph per line.
    /// Lines inside a paragraph are joined with a space (none next to CJK text).
    static func paragraphs(in text: String) -> [String] {
        let lines = text
            .replacing("\r\n", with: "\n")
            .replacing("\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let hasBlankLines: Bool
        if let first = lines.firstIndex(where: { !$0.isEmpty }), let last = lines.lastIndex(where: { !$0.isEmpty }) {
            hasBlankLines = lines[first...last].contains { $0.isEmpty }
        } else {
            hasBlankLines = false
        }
        if !hasBlankLines { return lines.filter { !$0.isEmpty } }

        var result: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty { result.append(current) }
            current = ""
        }
        for line in lines {
            if line.isEmpty {
                flush()
            } else if current.isEmpty {
                current = line
            } else {
                let joinsWithoutSpace = current.last.map(ScriptTraits.isCJK) == true
                    || line.first.map(ScriptTraits.isCJK) == true
                current += (joinsWithoutSpace ? "" : " ") + line
            }
        }
        flush()
        return result
    }

    /// A short line without closing punctuation that is entirely upper-case in a script that has case.
    static func isCapitalsHeading(_ paragraph: String) -> Bool {
        guard paragraph.count <= maxCapitalsHeadingLength,
              let last = paragraph.last, !ScriptTraits.isSentenceTerminal(last) else { return false }
        return paragraph == paragraph.uppercased() && paragraph != paragraph.lowercased()
    }
}
