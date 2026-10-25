import Foundation
import EbookCore

/// Imports and writes books; abstracts `BookConverter` so the view model can be tested with fakes.
public protocol BookConverting: Sendable {
    func importBook(from url: URL, context: ImportContext) async throws -> ImportResult
    func write(_ document: BookDocument, cover: ImageAsset?, as format: OutputFormat) throws -> Data
}

extension BookConverter: BookConverting {}
