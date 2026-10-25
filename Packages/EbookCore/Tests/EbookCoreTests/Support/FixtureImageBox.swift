import CoreGraphics
@testable import EbookCore

/// An image drawn on page `page` at `rect` in a generated fixture PDF.
struct FixtureImageBox {
    var page: Int
    var rect: CGRect
    var image: ImageAsset
}
