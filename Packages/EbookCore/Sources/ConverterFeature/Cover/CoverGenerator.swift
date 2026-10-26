import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import EbookCore

/// Renders `GeneratedCoverView` into a 1200×1600 JPEG cover with id "cover".
@MainActor public struct CoverGenerator: CoverGenerating {
    private static let jpegQuality = 0.8

    public init() {}

    public func makeCover(title: String, author: String) -> ImageAsset? {
        let renderer = ImageRenderer(content: GeneratedCoverView(title: title, author: author))
        renderer.scale = 1
        renderer.isOpaque = true
        guard let image = renderer.cgImage else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: Self.jpegQuality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return ImageNormalizer.normalize(output as Data, id: "cover")
    }
}
