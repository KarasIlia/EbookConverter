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
    public private(set) var sizeStatus: BookSizeStatus = .computing
    /// Error of the last failed `grantFolderAccess` re-import, or of an `open` that was refused because the
    /// file's format is not supported; the loaded book is kept in both cases.
    public private(set) var lastError: ImportError?
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
    /// Title/author changed while the cover is generated; it is re-rendered after the debounce, not per keystroke.
    @ObservationIgnored private var needsCoverRegeneration = false

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

    /// Exact size in bytes of the output file; `nil` while computing or after a failed write.
    public var bookSize: Int? {
        if case .ready(let size) = sizeStatus { size } else { nil }
    }

    /// Title made safe for a file name, plus the output format's extension.
    public var suggestedFileName: String {
        let replaced = String(title.map { Self.forbiddenFileNameCharacters.contains($0) ? " " : $0 })
        let name = replaced.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (name.isEmpty ? "Book" : name) + "." + outputFormat.fileExtension
    }

    /// Imports the book at `url`, replacing the current one.
    ///
    /// While a book is loaded, a file that cannot be imported at all (unsupported format, empty, unreadable)
    /// does not replace it: the book and its edits stay and the error is reported in `lastError`.
    public func open(_ url: URL) async {
        importGeneration += 1
        let generation = importGeneration
        let converter = makeConverter(now())
        if document != nil {
            let check = await Self.checkFormat(of: url, using: converter)
            guard generation == importGeneration else { return }
            if case .failure(let error) = check {
                lastError = error
                return
            }
        }
        clearBook()
        state = .loading(fileName: url.lastPathComponent)

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
    /// Metadata edits and a custom cover are kept. If the re-import fails, the current book stays loaded
    /// and the error is reported in `lastError`.
    public func grantFolderAccess(_ folder: URL) async {
        guard let fileURL, let converter else { return }
        // A superseded grant returns without an outcome; it must not leave an earlier failure behind.
        lastError = nil
        importGeneration += 1
        let generation = importGeneration
        let outcome = await Self.importBook(
            from: fileURL, context: ImportContext(accessibleFolder: folder), using: converter, accessing: [fileURL, folder]
        )
        guard generation == importGeneration else { return }
        switch outcome {
        case .success(let result):
            lastError = nil
            apply(result, keepingEdits: true)
        case .failure(let error):
            lastError = error
        }
    }

    /// Uses the image in `data` as the cover. Data that is not a readable image is ignored.
    /// - Returns: `false` if `data` is not a readable image.
    @discardableResult public func setCustomCover(_ data: Data) -> Bool {
        guard let asset = ImageNormalizer.normalize(data, id: "cover") else { return false }
        customCover = asset
        refreshCover()
        return true
    }

    /// Drops the custom cover: back to the file's cover if any, else a generated one.
    public func resetCover() {
        customCover = nil
        refreshCover()
    }

    /// The output file: the document with edited metadata and the current cover, in `outputFormat`.
    /// Produces exactly `bookSize` bytes.
    public func exportData() throws -> Data {
        regeneratePendingCover()
        guard let converter, let document = editedDocument() else { throw ExportError.noDocument }
        return try converter.write(document, cover: cover, as: outputFormat)
    }

    /// Test hook: waits for the size computation in flight, if any.
    public func waitForSizeComputation() async {
        await sizeTask?.value
    }

    // MARK: - Private

    /// Runs the import off the main actor (importers that need it hop back themselves).
    @concurrent private static func importBook(
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

    /// Detects the file's format off the main actor, inside its security scope.
    @concurrent private static func checkFormat(of url: URL, using converter: any BookConverting) async -> Result<SourceFormat, ImportError> {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing { url.stopAccessingSecurityScopedResource() }
        }
        do {
            return .success(try converter.sourceFormat(of: url))
        } catch let error as ImportError {
            return .failure(error)
        } catch {
            return .failure(.unreadable(error.localizedDescription))
        }
    }

    /// Builds the output off the main actor and returns its size.
    @concurrent private static func measure(
        _ document: BookDocument, cover: ImageAsset?, format: OutputFormat, using converter: any BookConverting
    ) async -> Result<Int, any Error> {
        Result { try converter.write(document, cover: cover, as: format).count }
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
        refreshCover()  // assigning `cover` schedules the size computation
    }

    private func clearBook() {
        // Keep the cancelled task referenced so the next one waits for its write to finish.
        sizeTask?.cancel()
        isApplyingChanges = true
        needsCoverRegeneration = false
        lastError = nil
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
        sizeStatus = .computing
        isApplyingChanges = false
    }

    /// Applies the cover precedence custom > fromFile > generated.
    private func refreshCover() {
        guard document != nil else { return }
        needsCoverRegeneration = false
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
            needsCoverRegeneration = true
        }
        scheduleSizeComputation()
    }

    /// Re-renders a generated cover whose title/author changed, without scheduling another size computation.
    private func regeneratePendingCover() {
        guard needsCoverRegeneration else { return }
        needsCoverRegeneration = false
        guard coverSource == .generated, document != nil else { return }
        isApplyingChanges = true
        cover = coverGenerator.makeCover(title: title, author: author)
        isApplyingChanges = false
    }

    /// The document with the edited metadata, trimmed. A blank title falls back to the file's own title,
    /// then to the file name, then to "Book": EPUB and FB2 require one.
    private func editedDocument() -> BookDocument? {
        guard var document else { return nil }
        let titles = [title, document.metadata.title, fileURL?.deletingPathExtension().lastPathComponent ?? ""]
        let exportTitle = titles.lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Book"
        document.metadata = BookMetadata(
            title: exportTitle,
            author: author.trimmingCharacters(in: .whitespacesAndNewlines),
            language: language.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return document
    }

    /// Cancels the pending measurement and starts a debounced one for the current state.
    ///
    /// The new task first waits for the cancelled one to finish, so at most one write runs at a time.
    /// After the debounce it re-renders a pending generated cover and measures the current state.
    private func scheduleSizeComputation() {
        guard !isApplyingChanges else { return }
        let previous = sizeTask
        previous?.cancel()
        sizeStatus = .computing
        guard converter != nil, document != nil else { return }
        sizeTask = Task { [weak self] in
            await previous?.value
            do { try await Task.sleep(for: Self.sizeDebounce) } catch { return }
            guard let self else { return }
            regeneratePendingCover()
            guard let converter, let document = editedDocument() else { return }
            let result = await Self.measure(document, cover: cover, format: outputFormat, using: converter)
            guard !Task.isCancelled else { return }
            sizeStatus = switch result {
            case .success(let size): .ready(size)
            case .failure: .failed
            }
        }
    }
}
