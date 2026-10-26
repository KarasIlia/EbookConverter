import AppKit
import EbookCore

/// Decoded images of the previewed book, so each asset is decoded once rather than on every view update.
///
/// Not observable on purpose: filling the cache during rendering must not trigger another update.
@MainActor final class PreviewImageCache {
    private var images: [ImageAsset.ID: NSImage] = [:]

    /// The decoded image for `asset`, or `nil` if its data is not a readable image.
    func image(for asset: ImageAsset) -> NSImage? {
        if let cached = images[asset.id] { return cached }
        guard let image = NSImage(data: asset.data) else { return nil }
        images[asset.id] = image
        return image
    }
}
