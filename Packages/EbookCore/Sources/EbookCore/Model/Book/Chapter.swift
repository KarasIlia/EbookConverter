import Foundation

/// A chapter or part. A chapter with children is a part; its own blocks come before them.
public struct Chapter: Sendable, Hashable, Identifiable {
    public let id: UUID
    public var title: String?
    public var blocks: [Block]
    public var children: [Chapter]

    public init(id: UUID = UUID(), title: String? = nil, blocks: [Block] = [], children: [Chapter] = []) {
        self.id = id
        self.title = title
        self.blocks = blocks
        self.children = children
    }
}

extension Chapter {
    /// Concatenated run text; paragraphs and headings are joined by "\n". Images are skipped.
    public var plainText: String {
        blocks.compactMap { block -> String? in
            switch block {
            case .heading(_, let runs), .paragraph(let runs):
                runs.map(\.text).joined()
            case .image:
                nil
            }
        }
        .joined(separator: "\n")
    }
}
