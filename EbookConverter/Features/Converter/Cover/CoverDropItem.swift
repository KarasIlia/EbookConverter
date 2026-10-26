import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// An image dropped on the cover well: raw image data (Photos, browsers) or an image file (Finder).
enum CoverDropItem: Transferable {
    case imageData(Data)
    case file(URL)

    static var transferRepresentation: some TransferRepresentation {
        // Image data first, so a browser drag yields the picture rather than its web address.
        DataRepresentation(importedContentType: .jpeg) { CoverDropItem.imageData($0) }
        DataRepresentation(importedContentType: .png) { CoverDropItem.imageData($0) }
        DataRepresentation(importedContentType: .heic) { CoverDropItem.imageData($0) }
        DataRepresentation(importedContentType: .tiff) { CoverDropItem.imageData($0) }
        ProxyRepresentation(importing: { (url: URL) in CoverDropItem.file(url) })
    }

    /// The image bytes, or `nil` for a file that is not one of `SupportedTypes.coverImages` or cannot be read.
    /// Synchronous so a drop can be refused when the item is unreadable; dropped image files are small.
    func loadImageData() -> Data? {
        switch self {
        case .imageData(let data):
            data
        case .file(let url):
            Self.readImageFile(at: url)
        }
    }

    /// Reads an image file chosen by the user, inside its security scope, off the main actor.
    @concurrent static func imageData(at url: URL) async -> Data? {
        readImageFile(at: url)
    }

    private static func readImageFile(at url: URL) -> Data? {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { url.stopAccessingSecurityScopedResource() }
        }
        guard url.isFileURL,
              let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType,
              SupportedTypes.coverImages.contains(where: type.conforms(to:))
        else { return nil }
        return try? Data(contentsOf: url)
    }
}
