import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Converts arbitrary image data into the JPEG/PNG assets the writers accept.
public enum ImageNormalizer {
    private static let jpegQuality = 0.8

    /// Returns an asset whose `contentType` is `.jpeg` or `.png`, or `nil` if `data` is not a readable image.
    ///
    /// Upright JPEG and PNG whose long side fits in `maxPixelSize` are kept byte-for-byte. Anything else
    /// (including images with an EXIF orientation other than 1) is re-encoded with the orientation applied,
    /// downscaled if needed, as JPEG, or as PNG when the image has an alpha channel.
    public static func normalize(_ data: Data, id: String, maxPixelSize: Int = 1600) -> ImageAsset? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }

        let sourceType = CGImageSourceGetType(source).flatMap { UTType($0 as String) }
        let longSide = max(width, height)
        // Readers such as PocketBook ignore EXIF orientation, so rotated images are re-encoded upright.
        let isUpright = (properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1
        if longSide <= maxPixelSize, isUpright, sourceType == .jpeg || sourceType == .png {
            return ImageAsset(id: id, data: data, contentType: sourceType ?? .jpeg, pixelWidth: width, pixelHeight: height)
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixelSize, longSide),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

        let hasAlpha = (properties[kCGImagePropertyHasAlpha] as? Bool) == true
        let type: UTType = hasAlpha ? .png : .jpeg
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else { return nil }
        let encodeOptions: [CFString: Any] = type == .jpeg
            ? [kCGImageDestinationLossyCompressionQuality: jpegQuality] : [:]
        CGImageDestinationAddImage(destination, image, encodeOptions as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return ImageAsset(id: id, data: output as Data, contentType: type, pixelWidth: image.width, pixelHeight: image.height)
    }
}
