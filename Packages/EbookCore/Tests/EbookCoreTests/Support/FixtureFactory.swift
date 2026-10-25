import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import EbookCore

enum FixtureFactory {
    /// A part of 2 chapters followed by 1 flat chapter, with styled runs, special characters and one image.
    static func sampleDocument(language: String = "en") -> BookDocument {
        let part = Chapter(
            title: "Part One",
            blocks: [.paragraph([InlineRun("Part intro.")])],
            children: [
                Chapter(title: "First", blocks: [
                    .paragraph([InlineRun("Plain "), InlineRun("bold", bold: true), InlineRun(" and "), InlineRun("italic", italic: true), InlineRun(".")]),
                    .paragraph([InlineRun("Fish & <chips> \"quoted\" 'single'")]),
                ]),
                Chapter(title: "Second", blocks: [
                    .heading(level: 1, runs: [InlineRun("Subheading")]),
                    .paragraph([InlineRun("Vertical\u{0B}tab removed.")]),
                    .image(pngImage(width: 2, height: 2)),
                ]),
            ]
        )
        let flat = Chapter(title: "Flat", blocks: [.paragraph([InlineRun("Last chapter.")])])
        return BookDocument(
            identifier: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID(),
            metadata: BookMetadata(title: "Sample & Book", author: "A. Writer", language: language),
            chapters: [part, flat]
        )
    }

    /// A solid-color PNG generated with CoreGraphics.
    static func pngImage(width: Int, height: Int, id: String = "img1") -> ImageAsset {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        if let image = context?.makeImage(),
           let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
        return ImageAsset(id: id, data: data as Data, contentType: .png, pixelWidth: width, pixelHeight: height)
    }

    /// Writes `attributed` in the given Word/RTF/HTML format to a fresh temporary folder.
    static func wordFile(_ attributed: NSAttributedString, type: NSAttributedString.DocumentType) throws -> URL {
        let data = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: type]
        )
        let fileExtension = switch type {
        case .officeOpenXML: "docx"
        case .docFormat: "doc"
        case .rtf: "rtf"
        case .html: "html"
        default: "dat"
        }
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "book.\(fileExtension)")
        try data.write(to: url)
        return url
    }
}
