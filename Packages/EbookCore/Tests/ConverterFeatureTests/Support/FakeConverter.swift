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
    private let failsWrites = Mutex(false)
    private let failsImports = Mutex(false)
    private let unsupportedURLs = Mutex<Set<URL>>([])

    init(result: Result<ImportResult, any Error>) {
        self.result = result
    }

    var recorded: Calls { calls.withLock { $0 } }

    /// When `true`, `importBook` throws a non-`ImportError`.
    func setFailsImports(_ fails: Bool) {
        failsImports.withLock { $0 = fails }
    }

    /// When `true`, `write` throws.
    func setFailsWrites(_ fails: Bool) {
        failsWrites.withLock { $0 = fails }
    }

    /// Files whose format is reported as unsupported (by `sourceFormat(of:)` and `importBook`).
    func setUnsupported(_ urls: Set<URL>) {
        unsupportedURLs.withLock { $0 = urls }
    }

    func sourceFormat(of url: URL) throws -> SourceFormat {
        if unsupportedURLs.withLock({ $0.contains(url) }) { throw ImportError.unsupportedFormat }
        return .txt
    }

    func importBook(from url: URL, context: ImportContext) async throws -> ImportResult {
        if unsupportedURLs.withLock({ $0.contains(url) }) { throw ImportError.unsupportedFormat }
        calls.withLock {
            $0.importedURLs.append(url)
            $0.contexts.append(context)
        }
        if failsImports.withLock({ $0 }) { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }

    func write(_ document: BookDocument, cover: ImageAsset?, as format: OutputFormat) throws -> Data {
        calls.withLock {
            $0.writtenFormats.append(format)
            $0.writtenDocuments.append(document)
            $0.writtenCovers.append(cover)
        }
        if failsWrites.withLock({ $0 }) { throw CocoaError(.fileWriteUnknown) }
        return Data(repeating: 0, count: format == .epub ? Self.epubSize : Self.fb2Size)
    }
}
