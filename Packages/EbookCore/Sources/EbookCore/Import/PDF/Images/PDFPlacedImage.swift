import CoreGraphics

/// An image drawn on a PDF page, rendered to a normalized asset.
public struct PDFPlacedImage: Sendable, Hashable {
    public var pageIndex: Int
    /// Placed rectangle in visible page space (crop box origin at 0,0, rotation applied, origin bottom-left),
    /// the same space as `PDFTextLine.bounds`.
    public var bounds: CGRect
    public var asset: ImageAsset

    public init(pageIndex: Int, bounds: CGRect, asset: ImageAsset) {
        self.pageIndex = pageIndex
        self.bounds = bounds
        self.asset = asset
    }
}
