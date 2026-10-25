import Foundation
import Synchronization
import EbookCore
@testable import ConverterFeature

/// Records calls and returns a canned import result (or throws) and fixed-size output per format.
final class FakeConverter: BookConverting {
    struct Calls {
        var importedURLs: [URL] = []
        var contexts: [ImportContext] = []
        var writtenFormats: [OutputFormat] = []
        var writtenDocuments: [BookDocument] = []
        var writtenCovers: [ImageAsset?] = []
    }

    static let epubSize = 100
    static let fb2Size = 250

    private let result: Result<ImportResult, any Error>
    private let calls = Mutex(Calls())

    init(result: Result<ImportResult, any Error>) {
        self.result = result
    }

    var recorded: Calls { calls.withLock { $0 } }

    func importBook(from url: URL, context: ImportContext) async throws -> ImportResult {
        calls.withLock {
            $0.importedURLs.append(url)
            $0.contexts.append(context)
        }
        return try result.get()
    }

    func write(_ document: BookDocument, cover: ImageAsset?, as format: OutputFormat) throws -> Data {
        calls.withLock {
            $0.writtenFormats.append(format)
            $0.writtenDocuments.append(document)
            $0.writtenCovers.append(cover)
        }
        return Data(repeating: 0, count: format == .epub ? Self.epubSize : Self.fb2Size)
    }
}
