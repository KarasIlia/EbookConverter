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
        // PDFKit selection bounds are in unrotated media-box space; normalise them to the visible page
        // (crop box origin at 0,0, rotation applied) so `bounds` always lies within `pageSize`.
        let crop = page.bounds(for: .cropBox)
        let rotation = normalizedRotation(page.rotation)
        let pageSize = rotation == 90 || rotation == 270
            ? CGSize(width: crop.height, height: crop.width) : crop.size
        let nsString = pageString as NSString
        var result: [PDFTextLine] = []

        nsString.enumerateSubstrings(in: NSRange(location: 0, length: nsString.length), options: [.byLines]) { _, range, _, _ in
            // Trim whitespace/newline characters so bounds and runs cover only visible text.
            let range = trimmed(range, in: nsString)
            guard range.length > 0,
                  let bounds = page.selection(for: range)?.bounds(for: page),
                  !bounds.isEmpty else { return }
            let visible = visibleBounds(bounds, crop: crop, rotation: rotation)
            guard !visible.isNull, !visible.isEmpty else { return }
            let (runs, fontSize) = styledRuns(in: attributed, range: range, fallback: nsString.substring(with: range))
            let text = runs.map(\.text).joined()
            guard !text.allSatisfy(\.isWhitespace) else { return }
            result.append(PDFTextLine(
                text: text, runs: runs, pageIndex: pageIndex,
                bounds: visible, fontSize: fontSize, pageSize: pageSize
            ))
        }
        return result
    }

    /// Maps a media-box-space point (e.g. an outline destination) to the visible page space used by line bounds.
    /// Points outside the crop box (including PDFKit's "unspecified" value) are clamped to its edges.
    static func visiblePoint(_ point: CGPoint, on page: PDFPage) -> CGPoint {
        let crop = page.bounds(for: .cropBox)
        let rotation = normalizedRotation(page.rotation)
        let x = min(max(point.x, crop.minX), crop.maxX) - crop.minX
        let y = min(max(point.y, crop.minY), crop.maxY) - crop.minY
        switch rotation {
        case 90: return CGPoint(x: y, y: crop.width - x)
        case 180: return CGPoint(x: crop.width - x, y: crop.height - y)
        case 270: return CGPoint(x: crop.height - y, y: x)
        default: return CGPoint(x: x, y: y)
        }
    }

    /// A page's `/Rotate` value as 0, 90, 180 or 270.
    static func normalizedRotation(_ rotation: Int) -> Int {
        ((rotation % 360) + 360) % 360
    }

    /// Maps a media-box-space rect to the displayed page: clipped to the crop box, shifted to the origin, rotated.
    /// Shared by text lines and images (`PDFImageExtractor`) so both live in the same coordinate space.
    /// `rotation` must be normalized (see `normalizedRotation`).
    static func visibleBounds(_ rect: CGRect, crop: CGRect, rotation: Int) -> CGRect {
        let clipped = rect.intersection(crop)
        guard !clipped.isNull else { return .null }
        let x = clipped.minX - crop.minX, y = clipped.minY - crop.minY
        let w = clipped.width, h = clipped.height
        switch rotation {
        case 90: return CGRect(x: y, y: crop.width - (x + w), width: h, height: w)
        case 180: return CGRect(x: crop.width - (x + w), y: crop.height - (y + h), width: w, height: h)
        case 270: return CGRect(x: crop.height - (y + h), y: x, width: h, height: w)
        default: return CGRect(x: x, y: y, width: w, height: h)
        }
    }

    static func trimmed(_ range: NSRange, in string: NSString) -> NSRange {
        var start = range.location
        var end = range.location + range.length
        // A UTF-16 surrogate half has no scalar of its own, so it is never whitespace.
        func isWhitespace(_ unit: unichar) -> Bool {
            Unicode.Scalar(unit).map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false
        }
        while start < end, isWhitespace(string.character(at: start)) { start += 1 }
        while end > start, isWhitespace(string.character(at: end - 1)) { end -= 1 }
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
