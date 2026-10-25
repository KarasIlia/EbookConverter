import Foundation
import EbookCore
@testable import ConverterFeature

/// Records requested titles/authors and returns a tiny placeholder asset.
@MainActor final class FakeCoverGenerator: CoverGenerating {
    private(set) var requests: [(title: String, author: String)] = []

    func makeCover(title: String, author: String) -> ImageAsset? {
        requests.append((title, author))
        return ImageAsset(id: "cover", data: Data(title.utf8), contentType: .jpeg, pixelWidth: 3, pixelHeight: 4)
    }
}
