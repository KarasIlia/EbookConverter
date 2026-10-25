import Foundation

/// Loads and normalizes images referenced from EPUB content documents, caching by archive path.
/// An asset's `id` is its archive path until the importer renumbers the images.
final class EPUBImageLoader {
    private let zip: ZipReader
    private var cache: [String: ImageAsset?] = [:]
    private(set) var remoteCount = 0
    private(set) var missingCount = 0

    init(zip: ZipReader) {
        self.zip = zip
    }

    /// The image `reference` points to, as seen from the document at `documentPath`.
    func load(_ reference: String, from documentPath: String) -> ImageAsset? {
        let lowered = reference.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") || lowered.hasPrefix("//") {
            remoteCount += 1
            return nil
        }
        guard let path = ArchivePath.resolve(reference, relativeTo: documentPath) else {
            missingCount += 1
            return nil
        }
        if let cached = cache[path] {
            if cached == nil { missingCount += 1 }
            return cached
        }
        let asset = (try? zip.data(for: path)).flatMap { ImageNormalizer.normalize($0, id: path) }
        cache[path] = .some(asset)
        if asset == nil { missingCount += 1 }
        return asset
    }
}
