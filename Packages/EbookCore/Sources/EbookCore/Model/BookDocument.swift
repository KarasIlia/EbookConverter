import Foundation

public struct BookDocument: Sendable, Hashable {
    public let identifier: UUID
    public var metadata: BookMetadata
    public var chapters: [Chapter]

    public init(identifier: UUID = UUID(), metadata: BookMetadata, chapters: [Chapter]) {
        self.identifier = identifier
        self.metadata = metadata
        self.chapters = chapters
    }
}

extension BookDocument {
    /// Chapters without children, in reading order (parts are flattened).
    public var leafChapters: [Chapter] {
        func leaves(of chapter: Chapter) -> [Chapter] {
            chapter.children.isEmpty ? [chapter] : chapter.children.flatMap(leaves(of:))
        }
        return chapters.flatMap(leaves(of:))
    }

    /// The chapter or part with `id`, searched depth-first through nested chapters.
    public func chapter(withID id: Chapter.ID) -> Chapter? {
        func find(in chapters: [Chapter]) -> Chapter? {
            for chapter in chapters {
                if chapter.id == id { return chapter }
                if let found = find(in: chapter.children) { return found }
            }
            return nil
        }
        return find(in: chapters)
    }

    /// Every image in the book, in reading order, including those in nested chapters.
    public var allImages: [ImageAsset] {
        func images(in chapter: Chapter) -> [ImageAsset] {
            let own = chapter.blocks.compactMap { block -> ImageAsset? in
                if case .image(let asset) = block { asset } else { nil }
            }
            return own + chapter.children.flatMap(images(in:))
        }
        return chapters.flatMap(images(in:))
    }
}
