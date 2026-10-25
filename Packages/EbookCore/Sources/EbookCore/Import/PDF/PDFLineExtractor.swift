import AppKit
import PDFKit

/// Splits PDF pages into lines with page-space bounds, font size and bold/italic runs, in PDFKit reading order.
public enum PDFLineExtractor {
    public static func lines(in document: PDFDocument) -> [PDFTextLine] {
        var result: [PDFTextLine] = []
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            result += lines(on: page, pageIndex: pageIndex)
        }
        return result
    }

    private static func lines(on page: PDFPage, pageIndex: Int) -> [PDFTextLine] {
        guard let pageString = page.string, !pageString.isEmpty else { return [] }
        let attributed = page.attributedString
        let pageSize = page.bounds(for: .mediaBox).size
        let nsString = pageString as NSString
        var result: [PDFTextLine] = []

        nsString.enumerateSubstrings(in: NSRange(location: 0, length: nsString.length), options: [.byLines]) { _, range, _, _ in
            // Trim whitespace/newline characters so bounds and runs cover only visible text.
            let range = trimmed(range, in: nsString)
            guard range.length > 0,
                  let bounds = page.selection(for: range)?.bounds(for: page),
                  !bounds.isEmpty else { return }
            let (runs, fontSize) = styledRuns(in: attributed, range: range, fallback: nsString.substring(with: range))
            let text = runs.map(\.text).joined()
            guard !text.allSatisfy(\.isWhitespace) else { return }
            result.append(PDFTextLine(
                text: text, runs: runs, pageIndex: pageIndex,
                bounds: bounds, fontSize: fontSize, pageSize: pageSize
            ))
        }
        return result
    }

    private static func trimmed(_ range: NSRange, in string: NSString) -> NSRange {
        var start = range.location
        var end = range.location + range.length
        let whitespace = CharacterSet.whitespacesAndNewlines
        while start < end, whitespace.contains(Unicode.Scalar(string.character(at: start)) ?? " ") { start += 1 }
        while end > start, whitespace.contains(Unicode.Scalar(string.character(at: end - 1)) ?? " ") { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    /// Runs (merged by identical style) and the dominant font size for `range`.
    private static func styledRuns(in attributed: NSAttributedString?, range: NSRange, fallback: String) -> ([InlineRun], Double) {
        guard let attributed, NSMaxRange(range) <= attributed.length else {
            return ([InlineRun(fallback)], 0)
        }
        var runs: [InlineRun] = []
        var sizeWeights: [Double: Int] = [:]
        attributed.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = value as? NSFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let name = font?.fontName.lowercased() ?? ""
            let bold = traits.contains(.bold) || ["bold", "semibold", "black", "heavy"].contains { name.contains($0) }
            let italic = traits.contains(.italic) || name.contains("italic") || name.contains("oblique")
            let text = attributed.attributedSubstring(from: subrange).string
            if let size = font?.pointSize {
                // Round to 0.1pt so tiny float noise doesn't split the vote.
                sizeWeights[(size * 10).rounded() / 10, default: 0] += text.count
            }
            if var last = runs.last, last.isBold == bold, last.isItalic == italic {
                last.text += text
                runs[runs.count - 1] = last
            } else {
                runs.append(InlineRun(text, bold: bold, italic: italic))
            }
        }
        let fontSize = sizeWeights.max { $0.value < $1.value }?.key ?? 0
        return (runs.isEmpty ? [InlineRun(fallback)] : runs, fontSize)
    }
}
