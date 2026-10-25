import CoreGraphics
import Foundation

/// Turns PDF lines into reflowable paragraphs: drops running headers and page numbers,
/// joins wrapped lines and repairs end-of-line hyphenation.
public enum PDFReflow {
    /// Fraction of the page height at the top and bottom where headers, footers and page numbers live.
    static let marginZone = 0.08
    /// A normalized line repeated on at least this share of pages (and `minimumRepeatPages`) is a running header.
    static let repeatPageShare = 0.3
    static let minimumRepeatPages = 3
    /// Paragraph break when lines' font sizes differ by more than this many points.
    static let fontSizeTolerance = 1.0
    /// Paragraph break when the vertical step exceeds this multiple of the page's median line spacing.
    static let gapRatio = 1.6
    /// Paragraph break when a line starts this many font sizes right (indent) or left (hanging line) of its column's body edge.
    static let indentRatio = 1.2
    /// Horizontal jump that means the text moved to another column; also the widest plausible indent.
    static let columnJump = 100.0
    /// Extra room, in font sizes, a line must leave at its end before the next line's first word counts as fitting.
    static let fitSlack = 0.5
    /// Share of the column width a line must stop short of the right edge by to count as ended on purpose.
    static let raggedShare = 0.15

    /// Characters that end a paragraph at a page or column boundary.
    private static let closingQuotes: Set<Character> = ["»", "\"", "”"]
    private static let softHyphen: Character = "\u{AD}"

    /// A paragraph with the line it starts on, so callers can locate it on the page.
    struct Located {
        var paragraph: StyledParagraph
        var firstLine: PDFTextLine
    }

    public static func paragraphs(from lines: [PDFTextLine]) -> [StyledParagraph] {
        locatedParagraphs(from: lines).map(\.paragraph)
    }

    /// Removes running headers/footers (repeated lines, digits ignored) and bare page numbers in the margins.
    public static func removingRunningHeaders(_ lines: [PDFTextLine]) -> [PDFTextLine] {
        let pageCount = Set(lines.map(\.pageIndex)).count
        var pagesByText: [String: Set<Int>] = [:]
        for line in lines {
            pagesByText[normalized(line.text), default: []].insert(line.pageIndex)
        }
        let threshold = max(Double(minimumRepeatPages), Double(pageCount) * repeatPageShare)
        // Geometry decides, not PDFKit order: a repeated header is removed wherever it appears in the text stream.
        let repeated = Set(pagesByText.filter { Double($0.value.count) >= threshold }.keys)
        return lines.filter { line in
            if repeated.contains(normalized(line.text)) { return false }
            return !(isInMarginZone(line) && isPageNumber(line.text))
        }
    }

    // MARK: - Running headers

    private static func normalized(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().map { $0.isNumber ? "#" : $0 })
    }

    private static func isInMarginZone(_ line: PDFTextLine) -> Bool {
        let height = line.pageSize.height
        guard height > 0 else { return false }
        let midY = line.bounds.midY
        return midY >= height * (1 - marginZone) || midY <= height * marginZone
    }

    private static func isPageNumber(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.wholeMatch(of: /\d{1,4}/) != nil
            || trimmed.wholeMatch(of: /(?i)m{0,3}(cm|cd|d?c{0,3})(xc|xl|l?x{0,3})(ix|iv|v?i{0,3})/) != nil
    }

    // MARK: - Paragraphs

    static func locatedParagraphs(from lines: [PDFTextLine]) -> [Located] {
        let spacing = medianLineSpacing(byPage: lines)
        let edges = columnEdges(of: lines)
        var result: [Located] = []
        for (index, line) in lines.enumerated() {
            if index > 0,
               !breaks(between: lines[index - 1], and: line, previousEdges: edges[index - 1], nextEdges: edges[index], spacing: spacing),
               var current = result.popLast() {
                current.paragraph.runs = joined(current.paragraph.runs, line.runs)
                result.append(current)
            } else {
                result.append(Located(paragraph: StyledParagraph(runs: line.runs, fontSize: line.fontSize), firstLine: line))
            }
        }
        return result
    }

    /// Median downward step between consecutive lines of each page.
    private static func medianLineSpacing(byPage lines: [PDFTextLine]) -> [Int: Double] {
        var steps: [Int: [Double]] = [:]
        for (previous, next) in zip(lines, lines.dropFirst()) where previous.pageIndex == next.pageIndex {
            let step = previous.bounds.midY - next.bounds.midY
            if step > 0 { steps[next.pageIndex, default: []].append(step) }
        }
        return steps.mapValues { values in
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }
    }

    /// Where a line's column has its body text: the most common left edge, and the right edge of same-size lines.
    private struct ColumnEdges {
        var left: Double
        var right: Double
    }

    /// Column edges for every line. A line's column is the page's lines starting less than a column jump away.
    private static func columnEdges(of lines: [PDFTextLine]) -> [ColumnEdges] {
        let indicesByPage = Dictionary(grouping: lines.indices, by: { lines[$0].pageIndex })
        var edges = lines.map { ColumnEdges(left: $0.bounds.minX, right: $0.bounds.maxX) }
        for indices in indicesByPage.values {
            for index in indices {
                let line = lines[index]
                let column = indices.map { lines[$0] }.filter { abs($0.bounds.minX - line.bounds.minX) < columnJump }
                // The body edge is the start most lines share (±2 pt), ties to the left: hanging first lines
                // and indented first lines are both exceptions to it.
                var buckets: [Int: Int] = [:]
                for other in column { buckets[Int(other.bounds.minX.rounded()), default: 0] += 1 }
                var best: (x: Int, count: Int)?
                for x in buckets.keys {
                    let count = (x - 2...x + 2).reduce(0) { $0 + (buckets[$1] ?? 0) }
                    if best.map({ count > $0.count || (count == $0.count && x < $0.x) }) ?? true { best = (x, count) }
                }
                if let best { edges[index].left = Double(best.x) }
                let sameSize = column.filter { abs($0.fontSize - line.fontSize) <= fontSizeTolerance }
                edges[index].right = sameSize.map { Double($0.bounds.maxX) }.max() ?? line.bounds.maxX
            }
        }
        return edges
    }

    private static func breaks(
        between previous: PDFTextLine, and next: PDFTextLine,
        previousEdges: ColumnEdges, nextEdges: ColumnEdges, spacing: [Int: Double]
    ) -> Bool {
        let previousText = previous.text.trimmingCharacters(in: .whitespaces)
        let endsSentence = previousText.last.map(isParagraphEnd) ?? false
        let samePage = previous.pageIndex == next.pageIndex
        let changesColumn = samePage && abs(next.bounds.minX - previous.bounds.minX) > columnJump
        if (!samePage || changesColumn) && endsSentence { return true }
        if abs(previous.fontSize - next.fontSize) > fontSizeTolerance { return true }
        if isAllBold(previous.runs) != isAllBold(next.runs) { return true }
        if samePage, !changesColumn {
            if let median = spacing[next.pageIndex], previous.bounds.midY - next.bounds.midY > gapRatio * median {
                return true
            }
            if endsEarly(previous, previousText: previousText, edges: previousEdges, before: next) { return true }
        }
        // Indented first line, or a hanging first line left of the body edge.
        let offset = next.bounds.minX - nextEdges.left
        return abs(offset) >= indentRatio * next.fontSize && abs(offset) < columnJump
    }

    /// `true` when `previous` stops clearly short of the column's right edge and `next`'s first word would have
    /// fitted there, so the line was ended on purpose.
    private static func endsEarly(_ previous: PDFTextLine, previousText: String, edges: ColumnEdges, before next: PDFTextLine) -> Bool {
        if let last = previousText.last, last == "-" || last == softHyphen { return false }
        let nextText = next.text.trimmingCharacters(in: .whitespaces)
        guard let first = nextText.first, !nextText.isEmpty else { return false }
        let averageCharacterWidth = next.bounds.width / Double(nextText.count)
        let wordLength = ScriptTraits.isCJK(first) ? 1 : nextText.prefix { !$0.isWhitespace }.count
        let needed = Double(wordLength + 1) * averageCharacterWidth + fitSlack * next.fontSize
        // Ragged-right text leaves uneven ends anyway, so only a clearly short line counts.
        let ragged = raggedShare * (edges.right - edges.left)
        return edges.right - previous.bounds.maxX > max(needed, ragged)
    }

    private static func isParagraphEnd(_ c: Character) -> Bool {
        ScriptTraits.isSentenceTerminal(c) || closingQuotes.contains(c)
    }

    private static func isAllBold(_ runs: [InlineRun]) -> Bool {
        StyledParagraph(runs: runs).isAllBold
    }

    // MARK: - Joining

    /// Appends `next` to `runs`, repairing hyphenation and spacing; adjacent runs with equal style merge.
    private static func joined(_ runs: [InlineRun], _ next: [InlineRun]) -> [InlineRun] {
        var result = runs
        guard var last = result.popLast() else { return next }
        let nextFirst = next.map(\.text).joined().first
        while last.text.last?.isWhitespace == true { last.text.removeLast() }
        if let end = last.text.last {
            if end == softHyphen {
                last.text.removeLast()
            } else if end == "-", last.text.dropLast().last.map({ !$0.isWhitespace }) ?? false {
                // A word broken at a hyphen: drop it before a lowercase continuation, keep it in compounds.
                if let nextFirst, ScriptTraits.isLowercaseLetter(nextFirst) { last.text.removeLast() }
            } else if let nextFirst, ScriptTraits.isCJK(end), ScriptTraits.isCJK(nextFirst) {
                // Scripts without word spaces join directly.
            } else {
                last.text += " "
            }
        }
        result.append(last)
        for run in next {
            if var tail = result.last, tail.isBold == run.isBold, tail.isItalic == run.isItalic {
                tail.text += run.text
                result[result.count - 1] = tail
            } else {
                result.append(run)
            }
        }
        return result.filter { !$0.text.isEmpty }
    }
}
