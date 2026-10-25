import Foundation

/// Imports EPUB 2 and 3 books: metadata, cover, spine content, and a two-level table of contents.
public struct EPUBImporter: BookImporter {
    /// Heading level for a chapter's own title when it differs from the table-of-contents label.
    private static let subheadingLevel = 3

    private let totalBudget: Int

    public init() {
        totalBudget = ZipReader.defaultTotalBudget
    }

    /// Test seam: a smaller limit on the total decompressed size.
    init(totalBudget: Int) {
        self.totalBudget = totalBudget
    }

    public func importBook(from url: URL, context: ImportContext) async throws -> ImportResult {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw ImportError.unreadable(error.localizedDescription) }
        let fallbackTitle = url.deletingPathExtension().lastPathComponent.replacing("_", with: " ")
        return try Self.makeResult(from: ZipReader(data: data, totalBudget: totalBudget), fallbackTitle: fallbackTitle)
    }

    // MARK: - Package

    private static func makeResult(from zip: ZipReader, fallbackTitle: String) throws -> ImportResult {
        let package = try readPackage(in: zip)
        let loader = EPUBImageLoader(zip: zip)

        let claims = tableOfContents(of: package, in: zip)
        let pages = spinePaths(of: package, in: zip)
        var chapters: [Chapter] = []
        var foundHeadings = !claims.isEmpty
        var damagedFileCount = 0
        var fallbackCover: ImageAsset?

        for (index, path) in pages.enumerated() {
            guard let data = try? zip.data(for: path) else {
                damagedFileCount += 1
                continue
            }
            let content = XHTMLBlockParser.parse(data) { loader.load($0, from: path) }
            if content.isTruncated { damagedFileCount += 1 }

            let images = content.blocks.compactMap { block -> ImageAsset? in
                if case .image(let asset) = block { asset } else { nil }
            }
            let isImageOnly = content.title == nil && !images.isEmpty && images.count == content.blocks.count
            if isImageOnly,
               images.contains(where: { $0.id == package.coverImagePath }) || path == package.guideCoverPath || index == 0 {
                // Cover page: the cover is returned separately; with none declared, the page's image is the cover.
                if package.coverImagePath == nil, index == 0, let image = images.first {
                    fallbackCover = ImageAsset(
                        id: "cover", data: image.data, contentType: image.contentType,
                        pixelWidth: image.pixelWidth, pixelHeight: image.pixelHeight
                    )
                }
                continue
            }

            var blocks = content.blocks
            let titleText = content.title.map(plainText)
            if let claim = claims[path] {
                let label = claim.title.isEmpty ? titleText : claim.title
                if let title = content.title, let titleText, titleText != label {
                    blocks.insert(.heading(level: subheadingLevel, runs: title), at: 0)
                }
                let chapter = Chapter(title: label, blocks: blocks)
                if claim.depth == 0 || chapters.isEmpty {
                    chapters.append(chapter)
                } else {
                    chapters[chapters.count - 1].children.append(chapter)
                }
            } else if claims.isEmpty {
                if titleText != nil { foundHeadings = true }
                if titleText != nil || chapters.isEmpty {
                    chapters.append(Chapter(title: titleText, blocks: blocks))
                } else {
                    append(blocks, to: &chapters)
                }
            } else {
                if let title = content.title { blocks.insert(.heading(level: subheadingLevel, runs: title), at: 0) }
                append(blocks, to: &chapters)
            }
        }

        if zip.isBudgetExhausted { throw ImportError.unreadable("Archive expands to too much data") }
        chapters = chapters.compactMap(pruned)
        guard !chapters.isEmpty else { throw ImportError.emptyDocument }
        var imageNumbers: [String: Int] = [:]
        chapters = chapters.map { renumbered($0, numbers: &imageNumbers) }

        var warnings: [ImportWarning] = []
        if loader.missingCount > 0 { warnings.append(.imagesUnavailable(count: loader.missingCount)) }
        if loader.remoteCount > 0 { warnings.append(.remoteImagesSkipped(count: loader.remoteCount)) }
        if damagedFileCount > 0 { warnings.append(.contentPartiallyUnreadable(count: damagedFileCount)) }

        var language = package.language.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        if language == nil {
            language = LanguageDetector.language(of: allText(of: chapters))
        }
        if language == nil { warnings.append(.languageUndetermined) }
        if !foundHeadings { warnings.append(.noChaptersFound) }

        let metadata = BookMetadata(
            title: package.title ?? fallbackTitle,
            author: package.authors.joined(separator: ", "),
            language: language ?? "und"
        )
        let cover = package.coverImagePath
            .flatMap { try? zip.data(for: $0) }
            .flatMap { ImageNormalizer.normalize($0, id: "cover") } ?? fallbackCover
        if zip.isBudgetExhausted { throw ImportError.unreadable("Archive expands to too much data") }
        return ImportResult(
            document: BookDocument(metadata: metadata, chapters: chapters), sourceCover: cover, warnings: warnings
        )
    }

    private static func readPackage(in zip: ZipReader) throws -> EPUBPackage {
        guard zip.paths.contains("META-INF/container.xml"),
              let container = XMLTreeNode.parse(try zip.data(for: "META-INF/container.xml")),
              let rootfile = container.firstDescendant(where: { $0.name == "rootfile" && $0.attributes["full-path"] != nil }),
              let opfPath = rootfile.attributes["full-path"].flatMap({ ArchivePath.resolve($0, relativeTo: "") }),
              zip.paths.contains(opfPath) else {
            throw ImportError.unreadable("Not an EPUB package")
        }
        guard let package = EPUBPackage.parse(try zip.data(for: opfPath), at: opfPath) else {
            throw ImportError.unreadable("Unreadable package document")
        }
        return package
    }

    /// Content documents in reading order, each once; only files that exist in the archive.
    private static func spinePaths(of package: EPUBPackage, in zip: ZipReader) -> [String] {
        let available = Set(zip.paths)
        var seen = Set<String>()
        return package.spine.compactMap { package.items[$0] }
            .filter { $0.isXHTML && !$0.properties.contains("nav") && available.contains($0.path) }
            .map(\.path)
            .filter { seen.insert($0).inserted }
    }

    /// Table-of-contents targets by file (fragments ignored); the first entry for a file wins.
    private static func tableOfContents(of package: EPUBPackage, in zip: ZipReader) -> [String: (title: String, depth: Int)] {
        let available = Set(zip.paths)
        var entries: [EPUBTableOfContents.Entry] = []
        if let nav = package.orderedItems.first(where: { $0.properties.contains("nav") && available.contains($0.path) }),
           let data = try? zip.data(for: nav.path) {
            entries = EPUBTableOfContents.parseNav(data, at: nav.path)
        }
        if entries.isEmpty {
            let ncx = package.tocID.flatMap { package.items[$0] }
                ?? package.orderedItems.first { $0.mediaType == "application/x-dtbncx+xml" }
            if let ncx, available.contains(ncx.path), let data = try? zip.data(for: ncx.path) {
                entries = EPUBTableOfContents.parseNCX(data, at: ncx.path)
            }
        }
        var claims: [String: (title: String, depth: Int)] = [:]
        for entry in EPUBTableOfContents.flattened(entries) where claims[entry.path] == nil {
            claims[entry.path] = (entry.title, entry.depth)
        }
        return claims
    }

    // MARK: - Chapter helpers

    private static func plainText(_ runs: [InlineRun]) -> String {
        runs.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Adds `blocks` to the last leaf chapter, creating an untitled chapter if there is none.
    private static func append(_ blocks: [Block], to chapters: inout [Chapter]) {
        guard !chapters.isEmpty else {
            chapters.append(Chapter(blocks: blocks))
            return
        }
        let last = chapters.count - 1
        if chapters[last].children.isEmpty {
            chapters[last].blocks.append(contentsOf: blocks)
        } else {
            chapters[last].children[chapters[last].children.count - 1].blocks.append(contentsOf: blocks)
        }
    }

    /// Drops chapters that have neither content nor sub-chapters.
    private static func pruned(_ chapter: Chapter) -> Chapter? {
        var chapter = chapter
        chapter.children = chapter.children.compactMap(pruned)
        return chapter.blocks.isEmpty && chapter.children.isEmpty ? nil : chapter
    }

    /// Gives images the ids `img-1`, `img-2`, ... in order of first appearance.
    private static func renumbered(_ chapter: Chapter, numbers: inout [String: Int]) -> Chapter {
        var chapter = chapter
        chapter.blocks = chapter.blocks.map { block in
            guard case .image(let asset) = block else { return block }
            let number = numbers[asset.id] ?? numbers.count + 1
            numbers[asset.id] = number
            return .image(ImageAsset(
                id: "img-\(number)", data: asset.data, contentType: asset.contentType,
                pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight
            ))
        }
        chapter.children = chapter.children.map { renumbered($0, numbers: &numbers) }
        return chapter
    }

    private static func allText(of chapters: [Chapter]) -> String {
        chapters.map { ([$0.plainText] + [allText(of: $0.children)]).joined(separator: "\n") }.joined(separator: "\n")
    }
}
