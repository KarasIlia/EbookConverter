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

    /// Fewest non-empty lines a file needs before it can be judged hard-wrapped.
    private static let minimumWrappedLines = 4
    /// Lines longer than this share of the wrap width count as filled to the margin.
    private static let fullLineShare = 0.75
    /// A file is hard-wrapped when at least this share of its lines is filled to the margin…
    private static let wrappedLineShare = 0.6
    /// …and its wrap width (90th percentile of line lengths) is at most this many characters.
    private static let maxWrapWidth = 100

    /// Splits text into paragraphs.
    ///
    /// Text with one paragraph per line (long lines of uneven length) yields every non-empty line as a paragraph.
    /// Hard-wrapped text (lines filled to a fixed width) starts a new paragraph at a blank line, at an indented
    /// line (unless most lines are indented) and after a short line ending a sentence; wrapped lines are joined
    /// by `LineJoiner`. In both modes a heading line (`HeadingPatterns` or ALL-CAPS) that starts a paragraph
    /// (or follows a finished sentence) stays a paragraph of its own.
    static func paragraphs(in text: String) -> [String] {
        let rawLines = text
            .replacing("\r\n", with: "\n")
            .replacing("\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
        let lines = rawLines.map { raw in
            (text: raw.trimmingCharacters(in: .whitespacesAndNewlines), isIndented: raw.first?.isWhitespace == true)
        }
        let nonEmpty = lines.filter { !$0.text.isEmpty }
        guard let wrapWidth = wrapWidth(of: nonEmpty.map(\.text.count)) else {
            return nonEmpty.map(\.text)
        }
        let fullLength = fullLineShare * Double(wrapWidth)
        let indentationMarksParagraphs = nonEmpty.count { $0.isIndented } * 2 < nonEmpty.count

        var result: [String] = []
        var current = ""
        var previous = ""
        func flush() {
            if !current.isEmpty { result.append(current) }
            current = ""
        }
        for line in lines {
            defer { previous = line.text }
            guard !line.text.isEmpty else {
                flush()
                continue
            }
            let previousEndsSentence = previous.last.map(ScriptTraits.isSentenceTerminal) == true
            if (line.isIndented && indentationMarksParagraphs) || (previousEndsSentence && Double(previous.count) < fullLength) {
                flush()
            }
            // After a finished sentence a heading line starts a paragraph even if the line before was full.
            if current.isEmpty || previousEndsSentence, isHeadingLine(line.text) {
                flush()
                result.append(line.text)
                continue
            }
            current = current.isEmpty ? line.text : LineJoiner.joined(current, line.text)
        }
        flush()
        return result
    }

    /// The wrap width of hard-wrapped text, or `nil` when lines are paragraphs of their own.
    private static func wrapWidth(of lengths: [Int]) -> Int? {
        guard lengths.count >= minimumWrappedLines else { return nil }
        let sorted = lengths.sorted()
        let width = sorted[Int(Double(sorted.count - 1) * 0.9)]
        guard width <= maxWrapWidth else { return nil }
        let full = lengths.count { Double($0) > fullLineShare * Double(width) }
        return Double(full) >= wrappedLineShare * Double(lengths.count) ? width : nil
    }

    /// A line that must not be glued to the text after it.
    private static func isHeadingLine(_ line: String) -> Bool {
        HeadingPatterns.partOrChapter(line) != nil || isCapitalsHeading(line)
    }

    /// A short line without closing punctuation that is entirely upper-case in a script that has case.
    static func isCapitalsHeading(_ paragraph: String) -> Bool {
        guard paragraph.count <= maxCapitalsHeadingLength,
              let last = paragraph.last, !ScriptTraits.isSentenceTerminal(last) else { return false }
        return paragraph == paragraph.uppercased() && paragraph != paragraph.lowercased()
    }
}
