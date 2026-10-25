import Foundation
import Observation
import EbookCore

/// State of the converter screen: the opened book, its editable metadata and cover, the output format
/// and the exact size of the file that `exportData()` would produce.
@Observable @MainActor public final class ConverterViewModel {
    /// Delay before measuring the output after an edit, so typing does not rebuild the book on every keystroke.
    private static let sizeDebounce = Duration.milliseconds(300)
    private static let forbiddenFileNameCharacters: Set<Character> = ["/", ":", "\\", "?", "%", "*", "|", "\"", "<", ">"]

    public private(set) var state: ConverterState = .empty
    public private(set) var document: BookDocument?
    public private(set) var warnings: [ImportWarning] = []

    public var title = "" {
        didSet { nameDidChange() }
    }

    public var author = "" {
        didSet { nameDidChange() }
    }

    public var language = "" {
        didSet { scheduleSizeComputation() }
    }

    public var outputFormat: OutputFormat = .epub {
        didSet { scheduleSizeComputation() }
    }

    public private(set) var cover: ImageAsset? {
        didSet { scheduleSizeComputation() }
    }

    public private(set) var coverSource: CoverSource = .generated
    /// Exact size in bytes of the output file; `nil` while it is being computed.
    public private(set) var bookSize: Int?
    public var selectedChapterID: Chapter.ID?

    @ObservationIgnored private let makeConverter: @Sendable (Date) -> any BookConverting
    @ObservationIgnored private let coverGenerator: any CoverGenerating
    @ObservationIgnored private let now: @Sendable () -> Date
    /// Converter of the opened book; created with the open time so repeated writes are byte-identical.
    @ObservationIgnored private var converter: (any BookConverting)?
    @ObservationIgnored private var fileURL: URL?
    @ObservationIgnored private var sourceCover: ImageAsset?
    @ObservationIgnored private var customCover: ImageAsset?
    @ObservationIgnored private var sizeTask: Task<Void, Never>?
    /// Incremented per import so a slow, superseded import cannot overwrite a newer one.
    @ObservationIgnored private var importGeneration = 0
    /// Suppresses cover regeneration and size computation while a batch of properties is assigned.
    @ObservationIgnored private var isApplyingChanges = false

    /// - Parameters:
    ///   - makeConverter: Creates the converter for each opened book from the open time.
    ///   - coverGenerator: Renders covers for books without one.
    ///   - now: Clock used for the open time.
    public init(
        makeConverter: @escaping @Sendable (Date) -> any BookConverting = { BookConverter(fixedDate: $0) },
        coverGenerator: any CoverGenerating = CoverGenerator(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.makeConverter = makeConverter
        self.coverGenerator = coverGenerator
        self.now = now
    }

    /// Title made safe for a file name, plus the output format's extension.
    public var suggestedFileName: String {
        let replaced = String(title.map { Self.forbiddenFileNameCharacters.contains($0) ? " " : $0 })
        let name = replaced.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (name.isEmpty ? "Book" : name) + "." + outputFormat.fileExtension
    }

    /// Imports the book at `url`, replacing the current one.
    public func open(_ url: URL) async {
        importGeneration += 1
        let generation = importGeneration
        clearBook()
        state = .loading(fileName: url.lastPathComponent)

        let converter = makeConverter(now())
        let outcome = await Self.importBook(from: url, context: ImportContext(), using: converter, accessing: [url])
        guard generation == importGeneration else { return }
        switch outcome {
        case .success(let result):
            self.converter = converter
            fileURL = url
            apply(result, keepingEdits: false)
        case .failure(let error):
            state = .failed(error)
        }
    }

    /// Re-imports the current file with access to `folder`, so images referenced by relative path resolve.
    /// Metadata edits and a custom cover are kept.
    public func grantFolderAccess(_ folder: URL) async {
        guard let fileURL, let converter else { return }
        importGeneration += 1
        let generation = importGeneration
        let outcome = await Self.importBook(
            from: fileURL, context: ImportContext(accessibleFolder: folder), using: converter, accessing: [fileURL, folder]
        )
        guard generation == importGeneration else { return }
        switch outcome {
        case .success(let result):
            apply(result, keepingEdits: true)
        case .failure(let error):
            clearBook()
            state = .failed(error)
        }
    }

    /// Uses the image in `data` as the cover. Data that is not a readable image is ignored.
    public func setCustomCover(_ data: Data) {
        guard let asset = ImageNormalizer.normalize(data, id: "cover") else { return }
        customCover = asset
        refreshCover()
    }

    /// Drops the custom cover: back to the file's cover if any, else a generated one.
    public func resetCover() {
        customCover = nil
        refreshCover()
    }

    /// The output file: the document with edited metadata and the current cover, in `outputFormat`.
    /// Produces exactly `bookSize` bytes.
    public func exportData() throws -> Data {
        guard let converter, let document = editedDocument() else { throw ExportError.noDocument }
        return try converter.write(document, cover: cover, as: outputFormat)
    }

    /// Test hook: waits for the size computation in flight, if any.
    public func waitForSizeComputation() async {
        await sizeTask?.value
    }

    // MARK: - Private

    private static func importBook(
        from url: URL, context: ImportContext, using converter: any BookConverting, accessing scopedURLs: [URL]
    ) async -> Result<ImportResult, ImportError> {
        let accessed = scopedURLs.filter { $0.startAccessingSecurityScopedResource() }
        defer { accessed.forEach { $0.stopAccessingSecurityScopedResource() } }
        do {
            return .success(try await converter.importBook(from: url, context: context))
        } catch let error as ImportError {
            return .failure(error)
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
    }

    /// Builds the output off the main actor and returns its size, or `nil` if writing failed.
    @concurrent private static func measure(
        _ document: BookDocument, cover: ImageAsset?, format: OutputFormat, using converter: any BookConverting
    ) async -> Int? {
        try? converter.write(document, cover: cover, as: format).count
    }

    private func apply(_ result: ImportResult, keepingEdits: Bool) {
        isApplyingChanges = true
        document = result.document
        warnings = result.warnings
        sourceCover = result.sourceCover
        if !keepingEdits {
            title = result.document.metadata.title
            author = result.document.metadata.author
            language = result.document.metadata.language
        }
        selectedChapterID = result.document.leafChapters.first?.id
        isApplyingChanges = false
        state = .loaded
        refreshCover()
        scheduleSizeComputation()
    }

    private func clearBook() {
        sizeTask?.cancel()
        sizeTask = nil
        isApplyingChanges = true
        converter = nil
        fileURL = nil
        document = nil
        warnings = []
        sourceCover = nil
        customCover = nil
        cover = nil
        coverSource = .generated
        title = ""
        author = ""
        language = ""
        selectedChapterID = nil
        bookSize = nil
        isApplyingChanges = false
    }

    /// Applies the cover precedence custom > fromFile > generated.
    private func refreshCover() {
        if let customCover {
            coverSource = .custom
            cover = customCover
        } else if let sourceCover {
            coverSource = .fromFile
            cover = sourceCover
        } else {
            coverSource = .generated
            cover = coverGenerator.makeCover(title: title, author: author)
        }
    }

    private func nameDidChange() {
        guard !isApplyingChanges, document != nil else { return }
        if coverSource == .generated {
            refreshCover()
        }
        scheduleSizeComputation()
    }

    private func editedDocument() -> BookDocument? {
        guard var document else { return nil }
        document.metadata = BookMetadata(title: title, author: author, language: language)
        return document
    }

    /// Cancels the pending measurement and starts a debounced one for the current state.
    private func scheduleSizeComputation() {
        guard !isApplyingChanges else { return }
        sizeTask?.cancel()
        sizeTask = nil
        bookSize = nil
        guard let converter, let document = editedDocument() else { return }
        let cover = cover
        let format = outputFormat
        sizeTask = Task { [weak self] in
            do { try await Task.sleep(for: Self.sizeDebounce) } catch { return }
            let size = await Self.measure(document, cover: cover, format: format, using: converter)
            guard !Task.isCancelled else { return }
            self?.bookSize = size
        }
    }
}
