/// Finds `<img src>` references in HTML so images are resolved by the app, not by WebKit.
enum HTMLImageReferences {
    /// Placeholder that still yields an attachment in `NSAttributedString` but loads nothing.
    static let placeholderSource = "about:blank"

    /// Returns `html` with every `<img>` `src` replaced by `placeholderSource`, and the original
    /// references (entity-decoded) in document order. `<img>` without `src` is left untouched.
    static func neutralize(_ html: String) -> (html: String, references: [String]) {
        let pattern = /(?i)<img\b[^>]*?\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/
        var output = ""
        var references: [String] = []
        var cursor = html.startIndex
        for match in html.matches(of: pattern) {
            guard let value = match.output.1 ?? match.output.2 ?? match.output.3 else { continue }
            output += html[cursor..<value.startIndex]
            output += placeholderSource
            cursor = value.endIndex
            references.append(decodeEntities(String(value)))
        }
        output += html[cursor...]
        return (output, references)
    }

    private static func decodeEntities(_ value: String) -> String {
        value
            .replacing("&quot;", with: "\"")
            .replacing("&#39;", with: "'")
            .replacing("&apos;", with: "'")
            .replacing("&lt;", with: "<")
            .replacing("&gt;", with: ">")
            .replacing("&amp;", with: "&")
    }
}
