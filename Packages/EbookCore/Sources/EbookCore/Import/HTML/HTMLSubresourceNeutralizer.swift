/// Prepares HTML for WebKit so it loads nothing: images are resolved by the app, other subresources are dropped.
enum HTMLSubresourceNeutralizer {
    /// Placeholder that still yields an attachment in `NSAttributedString` but loads nothing.
    static let placeholderSource = "about:blank"

    /// Returns `html` ready for WebKit, and the `<img src>` references (entity-decoded) in document order.
    ///
    /// Comments, `<script>`, `<noscript>` and `<template>` regions are removed (their `<img>` never render).
    /// Each `<img>` `src` becomes `placeholderSource`, so the n-th attachment is the n-th reference;
    /// `<img>` without `src` yields no attachment and no reference. `srcset`, `poster`, `<link>`,
    /// CSS `url(…)`/`@import` and `<iframe src>` are neutralized so no network load can happen.
    static func neutralize(_ html: String) -> (html: String, references: [String]) {
        let html = html
            .replacing(/(?s)<!--.*?-->/, with: "")
            .replacing(/(?is)<(script|noscript|template)\b.*?<\/\1\s*>/, with: "")
            .replacing(/(?i)<link\b[^>]*>/, with: "")
            .replacing(/(?is)(<style\b[^>]*>)(.*?)(<\/style\s*>)/) { match in
                match.output.1 + neutralizeCSS(String(match.output.2)) + match.output.3
            }
            .replacing(/<[A-Za-z][^>]*>/) { match in neutralizeTag(String(match.output)) }

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

    /// Drops `srcset`/`poster`, empties CSS `url(…)` in `style`, and blanks `<iframe src>` inside one start tag.
    private static func neutralizeTag(_ tag: String) -> String {
        var tag = tag.replacing(/(?i)\s(?:srcset|poster)\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)/, with: "")
        tag = tag.replacing(/(?i)(\sstyle\s*=\s*)("[^"]*"|'[^']*')/) { match in
            match.output.1 + neutralizeCSS(String(match.output.2))
        }
        if tag.firstMatch(of: /(?i)^<iframe\b/) != nil {
            tag = tag.replacing(/(?i)(\ssrc\s*=\s*)(?:"[^"]*"|'[^']*'|[^\s>]+)/) { match in
                match.output.1 + "\"\(placeholderSource)\""
            }
        }
        return tag
    }

    private static func neutralizeCSS(_ css: String) -> String {
        css
            .replacing(/(?i)@import\b[^;]*;?/, with: "")
            .replacing(/(?i)url\(\s*(?:"[^"]*"|'[^']*'|[^)]*)\s*\)/, with: "url()")
    }

    /// Decodes the named XML entities and numeric character references.
    static func decodeEntities(_ value: String) -> String {
        value
            .replacing(/&#(?:([0-9]+)|[xX]([0-9A-Fa-f]+));/) { match in
                let code = match.output.1.flatMap { UInt32($0) } ?? match.output.2.flatMap { UInt32($0, radix: 16) }
                return code.flatMap(Unicode.Scalar.init).map { String($0) } ?? String(match.output.0)
            }
            .replacing("&quot;", with: "\"")
            .replacing("&apos;", with: "'")
            .replacing("&lt;", with: "<")
            .replacing("&gt;", with: ">")
            .replacing("&nbsp;", with: "\u{00A0}")
            .replacing("&amp;", with: "&")
    }
}
