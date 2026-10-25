import Foundation

/// Reads a source file into the format-independent document model.
public protocol BookImporter: Sendable {
    func importBook(from url: URL, context: ImportContext) async throws -> ImportResult
}
