import EbookCore

/// Produces a cover image for books that have none.
@MainActor public protocol CoverGenerating {
    func makeCover(title: String, author: String) -> ImageAsset?
}
