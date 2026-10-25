import Foundation
import Synchronization
import EbookCore
@testable import ConverterFeature

/// A converter whose imports of `slowURL`, imports with a gated accessible folder, and writes
/// block until the test releases them. Imports with `failingFolder` throw.
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
    let failingFolder: URL?
    private let folderGates: [URL: (stream: AsyncStream<Void>, release: AsyncStream<Void>.Continuation)]
    private let foldersStarted = Mutex<[URL]>([])
    private let gatesWrites: Bool
    private let importGate: AsyncStream<Void>
    private let importRelease: AsyncStream<Void>.Continuation
    private let importsStarted = Mutex<[URL]>([])
    private let writes = Mutex(WriteState())

    init(slowURL: URL? = nil, gatesWrites: Bool = false, gatedFolders: [URL] = [], failingFolder: URL? = nil) {
        self.slowURL = slowURL
        self.failingFolder = failingFolder
        folderGates = Dictionary(uniqueKeysWithValues: gatedFolders.map { folder in
            let (stream, release) = AsyncStream<Void>.makeStream()
            return (folder, (stream, release))
        })
        self.gatesWrites = gatesWrites
        (importGate, importRelease) = AsyncStream<Void>.makeStream()
    }

    var startedImports: [URL] { importsStarted.withLock { $0 } }
    /// Accessible folders of the imports started so far.
    var startedFolders: [URL] { foldersStarted.withLock { $0 } }
    var writeState: WriteState { writes.withLock { $0 } }

    func releaseSlowImport() {
        importRelease.finish()
    }

    func releaseImports(withFolder folder: URL) {
        folderGates[folder]?.release.finish()
    }

    func releaseNextWrite() {
        writes.withLock { $0.released += 1 }
    }

    func sourceFormat(of url: URL) throws -> SourceFormat {
        .txt
    }

    func importBook(from url: URL, context: ImportContext) async throws -> ImportResult {
        importsStarted.withLock { $0.append(url) }
        if let folder = context.accessibleFolder {
            foldersStarted.withLock { $0.append(folder) }
            if folder == failingFolder { throw ImportError.unreadable("denied") }
            if let gate = folderGates[folder] {
                for await _ in gate.stream {}
            }
        }
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
