import Foundation

/// Converts one XHTML content document into blocks.
public enum XHTMLBlockParser {
    /// The parsed document: its title heading (if the file opens with `h1`/`h2`) and the remaining blocks.
    public struct Content: Sendable, Hashable {
        public var title: [InlineRun]?
        public var blocks: [Block]
        /// `true` if a parse error cut the document short, so some content may be missing.
        public var isTruncated = false
    }

    /// Blocks of `xhtml` without the leading chapter title heading.
    /// - Parameter resolveImage: receives the raw `src` / `href` of each image; `nil` drops the image.
    public static func blocks(from xhtml: Data, resolveImage: (String) -> ImageAsset?) -> [Block] {
        parse(xhtml, resolveImage: resolveImage).blocks
    }

    /// Parses `xhtml`. Malformed markup keeps everything read before the error.
    public static func parse(_ xhtml: Data, resolveImage: (String) -> ImageAsset?) -> Content {
        withoutActuallyEscaping(resolveImage) { resolve in
            let collector = Collector(resolveImage: resolve)
            let parser = XMLParser(data: XHTMLEntities.sanitized(xhtml))
            parser.shouldResolveExternalEntities = false
            parser.delegate = collector
            parser.parse()
            collector.flush()
            return Content(title: collector.title, blocks: collector.blocks, isTruncated: collector.hasParseError)
        }
    }

    private final class Collector: NSObject, XMLParserDelegate {
        private static let blockNames: Set<String> = [
            "p", "div", "li", "blockquote", "tr", "td", "th", "dt", "dd", "pre", "section", "article", "aside",
            "header", "footer", "figure", "figcaption", "ul", "ol", "dl", "table", "body", "nav", "address",
        ]
        private static let skippedNames: Set<String> = ["head", "script", "style"]
        private static let headingNames: [String: Int] = ["h1": 1, "h2": 2, "h3": 3, "h4": 4, "h5": 5, "h6": 6]

        private let resolveImage: (String) -> ImageAsset?
        private(set) var blocks: [Block] = []
        private(set) var title: [InlineRun]?
        private(set) var hasParseError = false

        private var runs: [InlineRun] = []
        private var headingLevel: Int?
        private var titleStillPossible = true
        private var boldDepth = 0
        private var italicDepth = 0
        private var skipDepth = 0

        init(resolveImage: @escaping (String) -> ImageAsset?) {
            self.resolveImage = resolveImage
        }

        func parser(
            _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
            qualifiedName qName: String?, attributes attributeDict: [String: String]
        ) {
            let name = XMLTreeNode.localName(elementName)
            if Self.skippedNames.contains(name) { skipDepth += 1 }
            guard skipDepth == 0 else { return }

            if let level = Self.headingNames[name] {
                flush()
                headingLevel = level
            } else if Self.blockNames.contains(name) {
                flush()
            }
            switch name {
            case "b", "strong": boldDepth += 1
            case "i", "em": italicDepth += 1
            case "br": runs.append(InlineRun(" "))
            case "img": appendImage(reference: attribute("src", in: attributeDict))
            case "image": appendImage(reference: attribute("href", in: attributeDict))
            default: break
            }
        }

        func parser(
            _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?
        ) {
            let name = XMLTreeNode.localName(elementName)
            if Self.skippedNames.contains(name) {
                skipDepth = max(0, skipDepth - 1)
                return
            }
            guard skipDepth == 0 else { return }

            if Self.headingNames[name] != nil {
                flush()
                headingLevel = nil
            } else if Self.blockNames.contains(name) {
                flush()
            }
            switch name {
            case "b", "strong": boldDepth = max(0, boldDepth - 1)
            case "i", "em": italicDepth = max(0, italicDepth - 1)
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard skipDepth == 0 else { return }
            let collapsed = Self.collapseWhitespace(string)
            guard !collapsed.isEmpty else { return }
            runs.append(InlineRun(collapsed, bold: boldDepth > 0, italic: italicDepth > 0))
        }

        func parser(_ parser: XMLParser, parseErrorOccurred parseError: any Error) {
            hasParseError = true
        }

        // MARK: - Building

        /// Turns the pending runs into a heading, the title or a paragraph.
        func flush() {
            let cleaned = Self.clean(runs)
            runs = []
            guard !cleaned.isEmpty else { return }
            if let level = headingLevel {
                if titleStillPossible, level <= 2 {
                    title = cleaned
                } else {
                    blocks.append(.heading(level: min(level, 3), runs: cleaned))
                }
            } else {
                blocks.append(.paragraph(cleaned))
            }
            titleStillPossible = false
        }

        private func appendImage(reference: String?) {
            flush()
            guard let reference, let asset = resolveImage(reference) else { return }
            blocks.append(.image(asset))
            titleStillPossible = false
        }

        private func attribute(_ name: String, in attributes: [String: String]) -> String? {
            attributes.first { XMLTreeNode.localName($0.key) == name }?.value
        }

        // MARK: - Whitespace

        /// Collapses runs of XML whitespace (space, tab, CR, LF) into one space; other whitespace such as NBSP stays.
        private static func collapseWhitespace(_ text: String) -> String {
            var result = String.UnicodeScalarView()
            var previousWasSpace = false
            for scalar in text.unicodeScalars {
                if scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" {
                    if !previousWasSpace { result.append(" ") }
                    previousWasSpace = true
                } else {
                    result.append(scalar)
                    previousWasSpace = false
                }
            }
            return String(result)
        }

        /// Merges neighbouring runs of equal style, removes doubled spaces across run borders and trims both ends.
        private static func clean(_ runs: [InlineRun]) -> [InlineRun] {
            var result: [InlineRun] = []
            var endsWithSpace = true // trims leading space
            for run in runs {
                var text = run.text
                if endsWithSpace, text.hasPrefix(" ") { text.removeFirst() }
                guard !text.isEmpty else { continue }
                endsWithSpace = text.hasSuffix(" ")
                if let last = result.last, last.isBold == run.isBold, last.isItalic == run.isItalic {
                    result[result.count - 1].text += text
                } else {
                    result.append(InlineRun(text, bold: run.isBold, italic: run.isItalic))
                }
            }
            if let last = result.last, last.text.hasSuffix(" ") {
                result[result.count - 1].text.removeLast()
                if result[result.count - 1].text.isEmpty { result.removeLast() }
            }
            return result
        }
    }
}
