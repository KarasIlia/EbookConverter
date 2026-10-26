import Foundation
import EbookCore

/// Imports and writes books; abstracts `BookConverter` so the view model can be tested with fakes.
public protocol BookConverting: Sendable {
    /// The format of the file at `url`; throws an `ImportError` if it cannot be imported at all.
    func sourceFormat(of url: URL) throws -> SourceFormat
    func importBook(from url: URL, context: ImportContext) async throws -> ImportResult
    func write(_ document: BookDocument, cover: ImageAsset?, as format: OutputFormat) throws -> Data
}

extension BookConverter: BookConverting {}
