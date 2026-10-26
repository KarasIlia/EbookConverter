import AppKit

/// Shortens a window title in the middle so it fits a given width. The system toolbar title
/// doesn't truncate next to the inspector, so the text is measured and shortened here.
@MainActor
enum TitleFitting {
    /// Font of the toolbar title, used for measuring.
    static let titleFont = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)

    /// `text` unchanged if it fits `width`; otherwise its start and end (e.g. the file extension) joined by "…",
    /// as long as fits. Works on grapheme clusters, so any script is safe.
    static func fitted(_ text: String, toWidth width: CGFloat, font: NSFont = titleFont) -> String {
        guard width > 0, measure(text, font: font) > width else { return text }
        let characters = Array(text)
        var low = 0, high = characters.count - 1
        var best = "…"
        while low <= high {
            let kept = (low + high) / 2
            let candidate = shortened(characters, keeping: kept)
            if measure(candidate, font: font) <= width {
                best = candidate
                low = kept + 1
            } else {
                high = kept - 1
            }
        }
        return best
    }

    private static func shortened(_ characters: [Character], keeping kept: Int) -> String {
        let tail = kept / 2
        let head = kept - tail
        return String(characters.prefix(head)) + "…" + String(characters.suffix(tail))
    }

    private static func measure(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}
