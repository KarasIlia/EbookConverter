import Foundation

/// Serializes a `BookDocument` into the bytes of an output file.
public protocol BookWriter: Sendable {
    func write(_ document: BookDocument, cover: ImageAsset?) throws -> Data
}
