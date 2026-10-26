import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import EbookCore

@Suite struct ImageNormalizerTests {
    private func encoded(_ width: Int, _ height: Int, type: UTType) throws -> Data {
        // FixtureFactory produces PNG; re-encode for other types.
        let png = FixtureFactory.pngImage(width: width, height: height).data
        if type == .png { return png }
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let out = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return out as Data
    }

    @Test func normalizerDownscalesLargeImage() throws {
        let data = try encoded(3000, 2000, type: .png)
        let asset = try #require(ImageNormalizer.normalize(data, id: "img-1"))
        #expect(max(asset.pixelWidth, asset.pixelHeight) == 1600)
        #expect(asset.pixelWidth == 1600)
        #expect(asset.contentType == .png)  // fixture has an alpha channel
        #expect(asset.id == "img-1")
    }

    @Test func normalizerKeepsSmallJPEG() throws {
        let data = try encoded(300, 200, type: .jpeg)
        let asset = try #require(ImageNormalizer.normalize(data, id: "img-2"))
        #expect(asset.data == data)
        #expect(asset.contentType == .jpeg)
        #expect(asset.pixelWidth == 300)
        #expect(asset.pixelHeight == 200)
    }

    @Test func rotatedJPEGIsReencodedUpright() throws {
        let png = FixtureFactory.pngImage(width: 300, height: 200).data
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let out = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let data = out as Data

        let asset = try #require(ImageNormalizer.normalize(data, id: "img-7"))
        #expect(asset.data != data)
        #expect(asset.contentType == .jpeg)
        #expect(asset.pixelWidth == 200 && asset.pixelHeight == 300)
        let written = try #require(CGImageSourceCreateWithData(asset.data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(written, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 200)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 300)
        #expect((properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
    }

    @Test func normalizerKeepsSmallPNG() throws {
        let data = try encoded(40, 30, type: .png)
        let asset = try #require(ImageNormalizer.normalize(data, id: "img-3"))
        #expect(asset.data == data)
        #expect(asset.contentType == .png)
    }

    @Test func normalizerDownscalesLargeJPEGToJPEG() throws {
        let data = try encoded(2400, 1200, type: .jpeg)
        let asset = try #require(ImageNormalizer.normalize(data, id: "img-4"))
        #expect(asset.contentType == .jpeg)
        #expect(asset.pixelWidth == 1600)
        #expect(asset.pixelHeight == 800)
    }

    @Test func normalizerReencodesTIFFAsJPEGOrPNG() throws {
        let data = try encoded(100, 100, type: .tiff)
        let asset = try #require(ImageNormalizer.normalize(data, id: "img-5"))
        #expect(asset.contentType == .jpeg || asset.contentType == .png)
        #expect(asset.data != data)
        #expect(asset.pixelWidth == 100)
    }

    @Test func normalizerRejectsGarbage() {
        #expect(ImageNormalizer.normalize(Data("not an image".utf8), id: "img-6") == nil)
    }
}
