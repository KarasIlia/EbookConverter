import Foundation

/// Converts an FB2 `body` element into chapters (two levels; deeper sections are flattened).
final class FB2BodyConverter {
    private static let subheadingLevel = 3
    /// Containers whose children are ordinary content.
    private static let containers: Set<String> = ["epigraph", "annotation", "cite", "poem", "stanza"]
    private static let lineNames: Set<String> = ["p", "v", "text-author"]

    private let images: FB2ImageResolver

    init(images: FB2ImageResolver) {
        self.images = images
    }

    func chapters(in body: XMLTreeNode) -> [Chapter] {
        let sections = body.children(named: "section")
        guard !sections.isEmpty else {
            return [Chapter(blocks: ownBlocks(of: body))]
        }
        // Content beside the sections (an epigraph, an image, opening paragraphs) leads the book untitled.
        let own = ownBlocks(of: body)
        return (own.isEmpty ? [] : [Chapter(blocks: own)]) + sections.map(topLevelChapter)
    }

    // MARK: - Chapters

    private func topLevelChapter(_ section: XMLTreeNode) -> Chapter {
        var blocks = ownBlocks(of: section)
        var childSections = section.children(named: "section")
        // The writer puts a part's own content into a leading untitled section; fold it back.
        if let first = childSections.first, title(of: first) == nil, first.children(named: "section").isEmpty {
            blocks += ownBlocks(of: first)
            childSections.removeFirst()
        }
        return Chapter(title: title(of: section), blocks: blocks, children: childSections.map(subChapter))
    }

    private func subChapter(_ section: XMLTreeNode) -> Chapter {
        Chapter(title: title(of: section), blocks: flattenedBlocks(of: section))
    }

    /// The section's content followed by that of its nested sections, whose titles become headings.
    private func flattenedBlocks(of section: XMLTreeNode) -> [Block] {
        var blocks = ownBlocks(of: section)
        for nested in section.children(named: "section") {
            if let title = titleRuns(of: nested) { blocks.append(.heading(level: Self.subheadingLevel, runs: title)) }
            blocks += flattenedBlocks(of: nested)
        }
        return blocks
    }

    // MARK: - Titles

    private func title(of section: XMLTreeNode) -> String? {
        titleRuns(of: section).map { $0.map(\.text).joined() }
    }

    /// The `title` element as one line of runs (multiple `p` joined by a space); `nil` if empty.
    private func titleRuns(of section: XMLTreeNode) -> [InlineRun]? {
        guard let title = section.firstChild(named: "title") else { return nil }
        let lines = title.children(named: "p").map(runs(of:)).filter { !$0.isEmpty }
        let combined = lines.isEmpty ? runs(of: title) : Array(lines.joined(separator: [InlineRun(" ")]))
        let normalized = Self.normalized(combined)
        return normalized.isEmpty ? nil : normalized
    }

    // MARK: - Blocks

    /// Content directly inside `node` (not inside nested `section` elements).
    private func ownBlocks(of node: XMLTreeNode) -> [Block] {
        var blocks: [Block] = []
        for child in node.children {
            switch child.name {
            case let name where Self.lineNames.contains(name):
                let runs = runs(of: child)
                if !runs.isEmpty { blocks.append(.paragraph(runs)) }
            case "subtitle":
                let runs = runs(of: child)
                if !runs.isEmpty { blocks.append(.heading(level: Self.subheadingLevel, runs: runs)) }
            case "image":
                if let image = images.bodyImage(for: child) { blocks.append(.image(image)) }
            case let name where Self.containers.contains(name):
                blocks += ownBlocks(of: child)
            default:
                break
            }
        }
        return blocks
    }

    // MARK: - Inline content

    /// Styled runs of `node`, with whitespace collapsed and the ends trimmed.
    private func runs(of node: XMLTreeNode) -> [InlineRun] {
        var collected: [InlineRun] = []
        collect(node, bold: false, italic: false, into: &collected)
        return Self.normalized(collected)
    }

    private func collect(_ node: XMLTreeNode, bold: Bool, italic: Bool, into runs: inout [InlineRun]) {
        for piece in node.pieces {
            switch piece {
            case .text(let text):
                runs.append(InlineRun(text, bold: bold, italic: italic))
            case .element(let child):
                switch child.name {
                case "image": break
                case "strong": collect(child, bold: true, italic: italic, into: &runs)
                case "emphasis": collect(child, bold: bold, italic: true, into: &runs)
                default: collect(child, bold: bold, italic: italic, into: &runs)
                }
            }
        }
    }

    /// Collapses XML whitespace, merges neighbours with equal styles, trims both ends and drops empty runs.
    private static func normalized(_ runs: [InlineRun]) -> [InlineRun] {
        var result: [InlineRun] = []
        for run in runs {
            var text = collapsingWhitespace(run.text)
            if text.isEmpty { continue }
            if text.hasPrefix(" "), result.last?.text.hasSuffix(" ") ?? true { text.removeFirst() }
            if text.isEmpty { continue }
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

    /// Replaces each run of XML whitespace (space, tab, CR, LF) with one space; other characters are kept.
    private static func collapsingWhitespace(_ text: String) -> String {
        var output = String.UnicodeScalarView()
        var previousWasSpace = false
        for scalar in text.unicodeScalars {
            if [0x20, 0x09, 0x0A, 0x0D].contains(scalar.value) {
                if !previousWasSpace { output.append(" ") }
                previousWasSpace = true
            } else {
                output.append(scalar)
                previousWasSpace = false
            }
        }
        return String(output)
    }
}
