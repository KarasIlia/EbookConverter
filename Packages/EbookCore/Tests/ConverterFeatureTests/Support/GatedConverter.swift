import Foundation
import Synchronization
import EbookCore
@testable import ConverterFeature

/// A converter whose imports of `slowURL` and whose writes block until the test releases them.
///
/// Imports return a document titled with the file name. Write number `n` (0-based) returns `1000 + n` bytes.
final class GatedConverter: BookConverting {
    struct WriteState {
        var started = 0
        var released = 0
        var inFlight = 0
        var maxInFlight = 0
    }

    let slowURL: URL?
    private let gatesWrites: Bool
    private let importGate: AsyncStream<Void>
    private let importRelease: AsyncStream<Void>.Continuation
    private let importsStarted = Mutex<[URL]>([])
    private let writes = Mutex(WriteState())

    init(slowURL: URL? = nil, gatesWrites: Bool = false) {
        self.slowURL = slowURL
        self.gatesWrites = gatesWrites
        (importGate, importRelease) = AsyncStream<Void>.makeStream()
    }

    var startedImports: [URL] { importsStarted.withLock { $0 } }
    var writeState: WriteState { writes.withLock { $0 } }

    func releaseSlowImport() {
        importRelease.finish()
    }

    func releaseNextWrite() {
        writes.withLock { $0.released += 1 }
    }

    func importBook(from url: URL, context: ImportContext) async throws -> ImportResult {
        importsStarted.withLock { $0.append(url) }
        if url == slowURL {
            for await _ in importGate {}
        }
        let chapter = Chapter(title: "Only", blocks: [.paragraph([InlineRun("Text")])])
        let metadata = BookMetadata(title: url.deletingPathExtension().lastPathComponent, author: "", language: "en")
        return ImportResult(document: BookDocument(metadata: metadata, chapters: [chapter]))
    }

    func write(_ document: BookDocument, cover: ImageAsset?, as format: OutputFormat) throws -> Data {
        let index = writes.withLock { state in
            state.started += 1
            state.inFlight += 1
            state.maxInFlight = max(state.maxInFlight, state.inFlight)
            return state.started - 1
        }
        while gatesWrites, !writes.withLock({ $0.released > index }) {
            Thread.sleep(forTimeInterval: 0.005)
        }
        writes.withLock { $0.inFlight -= 1 }
        return Data(repeating: 0, count: 1000 + index)
    }
}
