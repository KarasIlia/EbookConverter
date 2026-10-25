import Foundation
import UniformTypeIdentifiers

/// An embedded image. `contentType` is `.jpeg` or `.png` after normalization.
public struct ImageAsset: Sendable, Hashable, Identifiable {
    public let id: String
    public var data: Data
    public var contentType: UTType
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(id: String, data: Data, contentType: UTType, pixelWidth: Int, pixelHeight: Int) {
        self.id = id
        self.data = data
        self.contentType = contentType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}
