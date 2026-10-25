import Foundation

/// A table of contents read from an EPUB 3 navigation document or an EPUB 2 NCX.
enum EPUBTableOfContents {
    struct Entry {
        var title: String
        /// Archive path of the target file (fragment removed); `nil` for unlinked group headings.
        var path: String?
        var children: [Entry]
    }

    /// Entries of the `epub:type="toc"` navigation in the nav document at `path`.
    static func parseNav(_ data: Data, at path: String) -> [Entry] {
        guard let root = XMLTreeNode.parse(data) else { return [] }
        let navs = root.descendants(named: "nav")
        let toc = navs.first { ($0.attributes["type"] ?? "").split(separator: " ").contains("toc") }
            ?? navs.first { $0.attributes["type"] == nil }
        guard let list = toc?.firstChild(named: "ol") ?? toc?.firstDescendant(where: { $0.name == "ol" }) else { return [] }
        return navEntries(in: list, basePath: path)
    }

    /// Entries of the NCX document at `path`.
    static func parseNCX(_ data: Data, at path: String) -> [Entry] {
        guard let root = XMLTreeNode.parse(data), let map = root.firstChild(named: "navmap") else { return [] }
        return ncxEntries(in: map, basePath: path)
    }

    /// The entries as an ordered list of `(entry, depth)` where depth is 0 (top level) or 1.
    /// Unlinked headings are dropped (their children move up); levels below 2 are folded into level 2.
    static func flattened(_ entries: [Entry]) -> [(title: String, path: String, depth: Int)] {
        func walk(_ entries: [Entry], depth: Int) -> [(title: String, path: String, depth: Int)] {
            entries.flatMap { entry -> [(title: String, path: String, depth: Int)] in
                guard let path = entry.path else { return walk(entry.children, depth: depth) }
                return [(entry.title, path, min(depth, 1))] + walk(entry.children, depth: depth + 1)
            }
        }
        return walk(entries, depth: 0)
    }

    private static func navEntries(in list: XMLTreeNode, basePath: String) -> [Entry] {
        list.children(named: "li").map { item in
            let label = item.children.first { $0.name == "a" || $0.name == "span" }
            let target = label?.name == "a" ? label?.attributes["href"] : nil
            return Entry(
                title: label?.collapsedText ?? "",
                path: target.flatMap { ArchivePath.resolve($0, relativeTo: basePath) },
                children: item.firstChild(named: "ol").map { navEntries(in: $0, basePath: basePath) } ?? []
            )
        }
    }

    private static func ncxEntries(in parent: XMLTreeNode, basePath: String) -> [Entry] {
        parent.children(named: "navpoint").map { point in
            Entry(
                title: point.firstChild(named: "navlabel")?.collapsedText ?? "",
                path: point.firstChild(named: "content")?.attributes["src"]
                    .flatMap { ArchivePath.resolve($0, relativeTo: basePath) },
                children: ncxEntries(in: point, basePath: basePath)
            )
        }
    }
}
