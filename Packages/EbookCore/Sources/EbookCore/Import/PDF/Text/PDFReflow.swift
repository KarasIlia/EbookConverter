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
    /// Paragraph break when a line starts this many font sizes right of its column's body edge (first-line indent).
    /// Typeset books indent by about 1 em or less, so this stays well below 1.
    static let indentRatio = 0.6
    /// Paragraph break when a line starts this many font sizes left of the body edge (hanging first line).
    /// Larger than `indentRatio`: optical margin alignment hangs quotes and dashes up to about half an em.
    static let hangingRatio = 1.2
    /// Widest shift, in font sizes, of a list item's wrapped line past the item's marker line.
    static let listContinuationRatio = 2.5
    /// Horizontal jump that means the text moved to another column; also the widest plausible indent.
    static let columnJump = 100.0
    /// Extra room, in font sizes, a line must leave at its end before the next line's first word counts as fitting.
    static let fitSlack = 0.5
    /// Share of the column width a line must stop short of the right edge by to count as ended on purpose.
    static let raggedShare = 0.15
    /// Share of a page's characters a left edge must carry to count as a column start for reordering.
    static let columnShare = 0.1

    /// Characters that end a paragraph at a page or column boundary.
    private static let closingQuotes: Set<Character> = ["»", "\"", "”"]
    private static let softHyphen: Character = "\u{AD}"

    /// A paragraph with its lines in reading order, so callers can locate it on the page.
    struct Located {
        var paragraph: StyledParagraph
        /// Never empty.
        var lines: [PDFTextLine]

        var firstLine: PDFTextLine {
            lines[0]
        }
    }

    public static func paragraphs(from lines: [PDFTextLine]) -> [StyledParagraph] {
        locatedParagraphs(from: lines).map(\.paragraph)
    }

    /// Removes running headers/footers and bare page numbers. Only lines in the top/bottom margin zones are
    /// candidates — geometry decides, whatever PDFKit's text order — so repeated mid-page lines
    /// ("Chapter 1", "Chapter 2"…) survive.
    public static func removingRunningHeaders(_ lines: [PDFTextLine]) -> [PDFTextLine] {
        let pageCount = Set(lines.map(\.pageIndex)).count
        var pagesByText: [String: Set<Int>] = [:]
        for line in lines where isInMarginZone(line) {
            pagesByText[normalized(line.text), default: []].insert(line.pageIndex)
        }
        let threshold = max(Double(minimumRepeatPages), Double(pageCount) * repeatPageShare)
        let repeated = Set(pagesByText.filter { Double($0.value.count) >= threshold }.keys)
        return lines.filter { line in
            guard isInMarginZone(line) else { return true }
            return !repeated.contains(normalized(line.text)) && !isPageNumber(line.text)
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
        let lines = orderedByColumns(lines)
        let spacing = medianLineSpacing(byPage: lines)
        let edges = columnEdges(of: lines)
        var result: [Located] = []
        for (index, line) in lines.enumerated() {
            if index > 0,
               !breaks(
                   between: lines[index - 1], and: line, paragraphStart: result.last?.firstLine,
                   previousEdges: edges[index - 1], nextEdges: edges[index], spacing: spacing
               ),
               var current = result.popLast() {
                current.paragraph.runs = joined(current.paragraph.runs, line.runs)
                current.lines.append(line)
                result.append(current)
            } else {
                result.append(Located(paragraph: StyledParagraph(runs: line.runs, fontSize: line.fontSize), lines: [line]))
            }
        }
        return result
    }

    // MARK: - Column order

    /// Keeps PDFKit order unless a page's text alternates between columns more than twice; such a page is
    /// re-read column by column (left to right, top-down) within bands separated by full-width lines.
    static func orderedByColumns(_ lines: [PDFTextLine]) -> [PDFTextLine] {
        var result: [PDFTextLine] = []
        var start = lines.startIndex
        while start < lines.endIndex {
            let page = lines[start].pageIndex
            let end = lines[start...].firstIndex { $0.pageIndex != page } ?? lines.endIndex
            result += orderedPage(Array(lines[start..<end]))
            start = end
        }
        return result
    }

    private static func orderedPage(_ lines: [PDFTextLine]) -> [PDFTextLine] {
        // Column starts: left edges carrying a real share of the page's text (short fill-in fragments don't),
        // at least a column jump apart.
        var characters: [Int: Int] = [:]
        for line in lines { characters[Int(line.bounds.minX.rounded()), default: 0] += line.text.count }
        let total = lines.reduce(0) { $0 + $1.text.count }
        var columnStarts: [Double] = []
        for x in characters.keys.sorted() {
            let share = (x - 2...x + 2).reduce(0) { $0 + (characters[$1] ?? 0) }
            guard Double(share) >= columnShare * Double(total) else { continue }
            if columnStarts.last.map({ Double(x) - $0 > columnJump }) ?? true { columnStarts.append(Double(x)) }
        }
        guard columnStarts.count >= 2 else { return lines }
        // A line belongs to the last column starting at most half a jump right of it (hanging headwords
        // sit a little left of their column's body text).
        func column(of line: PDFTextLine) -> Int {
            columnStarts.lastIndex { $0 <= line.bounds.minX + columnJump / 2 } ?? 0
        }
        // A line running well into the next column is full-width (single-column body text next to
        // centred headings is too, so such pages are never reordered).
        func isSpanning(_ line: PDFTextLine) -> Bool {
            let next = column(of: line) + 1
            return next < columnStarts.count && line.bounds.maxX > columnStarts[next] + columnJump / 2
        }
        let columns = lines.filter { !isSpanning($0) }.map(column(of:))
        let switches = zip(columns, columns.dropFirst()).count { $0 != $1 }
        guard switches > 2 else { return lines }

        let spanning = lines.filter(isSpanning).sorted { $0.bounds.midY > $1.bounds.midY }
        var bands = Array(repeating: [PDFTextLine](), count: spanning.count + 1)
        for line in lines where !isSpanning(line) {
            bands[spanning.count { $0.bounds.midY > line.bounds.midY }].append(line)
        }
        var result: [PDFTextLine] = []
        for (index, band) in bands.enumerated() {
            result += band.enumerated().sorted { lhs, rhs in
                let (a, b) = (lhs.element, rhs.element)
                if column(of: a) != column(of: b) { return column(of: a) < column(of: b) }
                if a.bounds.midY != b.bounds.midY { return a.bounds.midY > b.bounds.midY }
                return lhs.offset < rhs.offset
            }.map(\.element)
            if index < spanning.count { result.append(spanning[index]) }
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

    /// Where a line's column has its body text: the body left edge and the right margin of same-size lines.
    private struct ColumnEdges {
        var left: Double
        var right: Double
    }

    /// Column edges for every line. A line's column is the page's lines starting less than a column jump away.
    private static func columnEdges(of lines: [PDFTextLine]) -> [ColumnEdges] {
        let indicesByPage = Dictionary(grouping: lines.indices, by: { lines[$0].pageIndex })
        var edges = lines.map { ColumnEdges(left: $0.bounds.minX, right: $0.bounds.maxX) }
        for indices in indicesByPage.values {
            let pageLines = indices.map { lines[$0] }
            for index in indices {
                let line = lines[index]
                let column = pageLines.filter { abs($0.bounds.minX - line.bounds.minX) < columnJump }
                edges[index].left = leftEdge(of: column, inOrder: pageLines)
                edges[index].right = rightEdge(of: column.filter { abs($0.fontSize - line.fontSize) <= fontSizeTolerance })
                    ?? line.bounds.maxX
            }
        }
        return edges
    }

    /// The column's body edge. Normally the leftmost start (indented first lines are exceptions). When most
    /// lines start further right, the leftmost lines may be hanging first lines (dictionaries, bibliographies):
    /// that is accepted only if those lines usually run on into a line at the common start, i.e. a leftmost line
    /// followed by a common-start line rarely ends a sentence. In indented prose (dense dialogue) it does.
    private static func leftEdge(of column: [PDFTextLine], inOrder pageLines: [PDFTextLine]) -> Double {
        var buckets: [Int: Int] = [:]
        for line in column { buckets[Int(line.bounds.minX.rounded()), default: 0] += 1 }
        var common: (x: Int, count: Int)?
        for x in buckets.keys {
            let count = (x - 2...x + 2).reduce(0) { $0 + (buckets[$1] ?? 0) }
            if common.map({ count > $0.count || (count == $0.count && x < $0.x) }) ?? true { common = (x, count) }
        }
        let minimum = column.map { Double($0.bounds.minX) }.min() ?? 0
        guard let common, Double(common.x) - minimum > 2 else { return minimum }
        let commonX = Double(common.x)
        var runOns = 0, endings = 0
        for (line, next) in zip(pageLines, pageLines.dropFirst())
        where abs(line.bounds.minX - minimum) <= 2 && abs(next.bounds.minX - commonX) <= 2 {
            let endsSentence = line.text.trimmingCharacters(in: .whitespaces).last.map(isParagraphEnd) ?? false
            if endsSentence { endings += 1 } else { runOns += 1 }
        }
        return runOns > endings ? commonX : minimum
    }

    /// The column's right margin: the 90th percentile end of lines of typical width, so a full-width line or
    /// one stray wide line does not make every column line look short.
    private static func rightEdge(of lines: [PDFTextLine]) -> Double? {
        guard !lines.isEmpty else { return nil }
        let widths = lines.map { Double($0.bounds.width) }.sorted()
        let typicalWidth = widths[widths.count / 2]
        let ends = lines.filter { Double($0.bounds.width) <= typicalWidth * 1.3 }.map { Double($0.bounds.maxX) }.sorted()
        guard !ends.isEmpty else { return nil }
        return ends[min(ends.count - 1, Int(Double(ends.count) * 0.9))]
    }

    private static func breaks(
        between previous: PDFTextLine, and next: PDFTextLine, paragraphStart: PDFTextLine?,
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
        // Indented first line, or a hanging first line left of the body edge. A fragment on the same baseline
        // (text after a fill-in blank) continues its line, whatever its start.
        if samePage, !changesColumn, abs(previous.bounds.midY - next.bounds.midY) < next.fontSize / 2 { return false }
        let offset = next.bounds.minX - nextEdges.left
        if offset > 0, [paragraphStart, previous].contains(where: { $0.map { isListContinuation(next, of: $0) } ?? false }) {
            return false
        }
        let threshold = (offset > 0 ? indentRatio : hangingRatio) * next.fontSize
        return abs(offset) >= threshold && abs(offset) < columnJump
    }

    /// `true` when the paragraph is a list item (`4 the internet…`, `b) …`, `• …`) and `next` is its wrapped
    /// continuation, aligned after the marker rather than indented as a new paragraph.
    private static func isListContinuation(_ next: PDFTextLine, of start: PDFTextLine) -> Bool {
        let text = start.text.trimmingCharacters(in: .whitespaces)
        let shift = next.bounds.minX - start.bounds.minX
        return shift > 0 && shift <= listContinuationRatio * next.fontSize
            && startsWithListMarker(text) && !startsWithListMarker(next.text)
    }

    /// A list marker followed by a space: up to three digits or a letter (optionally with `.`/`)`), or a bullet.
    private static func startsWithListMarker(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces)
            .wholeMatch(of: /(?:\d{1,3}[.)]?|\p{L}[.)]|[•●▪◦‣∙*–—-])\s+\S.*/) != nil
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
        LineJoiner.prepare(&last.text, before: next.map(\.text).joined().first)
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
