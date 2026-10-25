import Foundation

/// The parts of an OPF package document the importer needs.
struct EPUBPackage {
    struct Item {
        var id: String
        /// Archive path, already normalized.
        var path: String
        var mediaType: String
        var properties: Set<String>

        var isXHTML: Bool {
            let type = mediaType.lowercased()
            return type == "application/xhtml+xml" || type == "text/html"
        }
    }

    var title: String?
    var authors: [String] = []
    var language: String?
    var items: [String: Item] = [:]
    /// Manifest items in document order (first declaration of an id wins).
    var orderedItems: [Item] = []
    /// `idref`s of the spine in reading order.
    var spine: [String] = []
    var tocID: String?
    /// Archive path of the cover image, from `properties="cover-image"` or `<meta name="cover">`.
    var coverImagePath: String?
    /// Archive path of the page the `<guide>` calls the cover.
    var guideCoverPath: String?

    /// Parses the OPF stored at `path`; `nil` if it is not a package document.
    static func parse(_ data: Data, at path: String) -> EPUBPackage? {
        guard let root = XMLTreeNode.parse(data), root.name == "package" else { return nil }
        var package = EPUBPackage()

        if let metadata = root.firstChild(named: "metadata") {
            package.title = metadata.children(named: "title").map(\.collapsedText).first { !$0.isEmpty }
            package.authors = metadata.children(named: "creator").map(\.collapsedText).filter { !$0.isEmpty }
            package.language = metadata.children(named: "language").map(\.collapsedText).first { !$0.isEmpty }
        }

        for element in root.firstChild(named: "manifest")?.children(named: "item") ?? [] {
            guard let id = element.attributes["id"],
                  let href = element.attributes["href"],
                  let itemPath = ArchivePath.resolve(href, relativeTo: path) else { continue }
            let properties = Set((element.attributes["properties"] ?? "").split(separator: " ").map(String.init))
            guard package.items[id] == nil else { continue }
            let item = Item(
                id: id, path: itemPath, mediaType: element.attributes["media-type"] ?? "", properties: properties
            )
            package.items[id] = item
            package.orderedItems.append(item)
        }

        let spine = root.firstChild(named: "spine")
        package.spine = (spine?.children(named: "itemref") ?? []).compactMap { $0.attributes["idref"] }
        package.tocID = spine?.attributes["toc"]

        let declaredCover = package.orderedItems.first { $0.properties.contains("cover-image") }
        let metaCover = root.firstChild(named: "metadata")?.children(named: "meta")
            .first { $0.attributes["name"]?.lowercased() == "cover" }
            .flatMap { $0.attributes["content"] }
            .flatMap { package.items[$0] }
        package.coverImagePath = [declaredCover, metaCover]
            .compactMap { $0 }
            .first { $0.mediaType.lowercased().hasPrefix("image/") }?.path

        package.guideCoverPath = root.firstChild(named: "guide")?.children(named: "reference")
            .first { $0.attributes["type"]?.lowercased() == "cover" }
            .flatMap { $0.attributes["href"] }
            .flatMap { ArchivePath.resolve($0, relativeTo: path) }
        return package
    }
}
