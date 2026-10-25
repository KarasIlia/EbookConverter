import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Image fixtures generated at test runtime.
enum TestImages {
    /// A solid-color PNG of the given size.
    static func png(width: Int, height: Int) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.7, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        if let image = context?.makeImage(),
           let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
        return data as Data
    }
}
