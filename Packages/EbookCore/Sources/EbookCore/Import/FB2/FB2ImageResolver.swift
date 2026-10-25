import Foundation

/// Resolves FB2 image references to normalized images decoded from `binary` elements.
final class FB2ImageResolver {
    private var encodedByID: [String: String] = [:]
    private var normalizedByID: [String: ImageAsset?] = [:]
    private var numbers: [String: Int] = [:]
    /// Body images whose binary is missing or not a readable image (each occurrence counts).
    private(set) var missingCount = 0

    init(binaries: [XMLTreeNode]) {
        for binary in binaries {
            guard let id = binary.attributes["id"], encodedByID[id] == nil else { continue }
            encodedByID[id] = binary.collapsedText
        }
    }

    /// The image for a body `image` element, numbered `img-1`, `img-2`, ... by first appearance; `nil` if unavailable.
    func bodyImage(for element: XMLTreeNode) -> ImageAsset? {
        guard let id = binaryID(of: element), let base = normalized(id) else {
            missingCount += 1
            return nil
        }
        let number = numbers[id] ?? numbers.count + 1
        numbers[id] = number
        return renamed(base, to: "img-\(number)")
    }

    /// The cover image for the `coverpage` image element, with id `cover`.
    func cover(for element: XMLTreeNode) -> ImageAsset? {
        binaryID(of: element).flatMap(normalized).map { renamed($0, to: "cover") }
    }

    private func binaryID(of element: XMLTreeNode) -> String? {
        guard let href = element.attributes["href"] else { return nil }
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
    }

    private func normalized(_ id: String) -> ImageAsset? {
        if let cached = normalizedByID[id] { return cached }
        let asset = encodedByID[id]
            .flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
            .flatMap { ImageNormalizer.normalize($0, id: id) }
        normalizedByID[id] = .some(asset)
        return asset
    }

    private func renamed(_ asset: ImageAsset, to id: String) -> ImageAsset {
        ImageAsset(
            id: id, data: asset.data, contentType: asset.contentType,
            pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight
        )
    }
}
