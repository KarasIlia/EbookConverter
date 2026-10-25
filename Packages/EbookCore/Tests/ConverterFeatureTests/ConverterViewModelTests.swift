import Foundation
import Testing
import EbookCore
@testable import ConverterFeature

@MainActor @Suite struct ConverterViewModelTests {
    private let bookURL = URL(filePath: "/tmp/ConverterViewModelTests/My Book.txt")
    private let sourceCover = ImageAsset(id: "src-cover", data: Data([1, 2, 3]), contentType: .jpeg, pixelWidth: 3, pixelHeight: 4)

    /// A part with two chapters followed by a flat chapter.
    private func document() -> BookDocument {
        let part = Chapter(title: "Part", blocks: [.paragraph([InlineRun("Intro")])], children: [
            Chapter(title: "One", blocks: [.paragraph([InlineRun("First text")])]),
            Chapter(title: "Two", blocks: [.paragraph([InlineRun("Second text")])]),
        ])
        let flat = Chapter(title: "Three", blocks: [.paragraph([InlineRun("Third text")])])
        return BookDocument(
            metadata: BookMetadata(title: "Война и мир", author: "Лев Толстой", language: "ru"),
            chapters: [part, flat]
        )
    }

    private func makeModel(
        cover: ImageAsset? = nil,
        warnings: [ImportWarning] = [],
        failure: (any Error)? = nil,
        originalTitle: String? = nil
    ) -> (ConverterViewModel, FakeConverter, FakeCoverGenerator) {
        var document = document()
        if let originalTitle { document.metadata.title = originalTitle }
        let result: Result<ImportResult, any Error> = if let failure {
            .failure(failure)
        } else {
            .success(ImportResult(document: document, sourceCover: cover, warnings: warnings))
        }
        let converter = FakeConverter(result: result)
        let generator = FakeCoverGenerator()
        let model = ConverterViewModel(makeConverter: { _ in converter }, coverGenerator: generator)
        return (model, converter, generator)
    }

    @Test func initialStateIsEmpty() {
        let (model, _, _) = makeModel()
        #expect(model.state == .empty)
        #expect(model.document == nil)
        #expect(model.outputFormat == .epub)
        #expect(model.bookSize == nil)
    }

    @Test func openSuccessLoadsMetadata() async {
        let (model, converter, _) = makeModel(warnings: [.languageUndetermined])
        await model.open(bookURL)

        #expect(model.state == .loaded)
        #expect(model.title == "Война и мир")
        #expect(model.author == "Лев Толстой")
        #expect(model.language == "ru")
        #expect(model.warnings == [.languageUndetermined])
        #expect(model.selectedChapterID == model.document?.leafChapters.first?.id)
        #expect(model.document?.leafChapters.first?.title == "One")
        #expect(converter.recorded.importedURLs == [bookURL])
        #expect(converter.recorded.contexts.first?.accessibleFolder == nil)
    }

    @Test func openFailureSetsFailedState() async {
        let (model, _, _) = makeModel(failure: ImportError.pdfHasNoTextLayer)
        await model.open(bookURL)
        #expect(model.state == .failed(.pdfHasNoTextLayer))
        #expect(model.document == nil)
    }

    @Test func nonImportErrorMapsToUnreadable() async {
        let error = CocoaError(.fileReadCorruptFile)
        let (model, _, _) = makeModel(failure: error)
        await model.open(bookURL)
        #expect(model.state == .failed(.unreadable(error.localizedDescription)))
    }

    @Test func coverPrecedence() async throws {
        let (model, _, generator) = makeModel(cover: sourceCover)
        await model.open(bookURL)
        #expect(model.coverSource == .fromFile)
        #expect(model.cover == sourceCover)
        #expect(generator.requests.isEmpty)

        #expect(model.setCustomCover(TestImages.png(width: 30, height: 40)))
        #expect(model.coverSource == .custom)
        let custom = try #require(model.cover)
        #expect(custom.id == "cover")
        #expect(custom.contentType == .png)
        #expect(custom.pixelWidth == 30 && custom.pixelHeight == 40)

        #expect(!model.setCustomCover(Data("not an image".utf8)))
        #expect(model.coverSource == .custom)
        #expect(model.cover == custom)

        model.resetCover()
        #expect(model.coverSource == .fromFile)
        #expect(model.cover == sourceCover)
    }

    @Test func noFileCoverFallsBackToGenerated() async {
        let (model, _, generator) = makeModel()
        await model.open(bookURL)
        #expect(model.coverSource == .generated)
        #expect(model.cover?.id == "cover")
        #expect(generator.requests.last?.title == "Война и мир")

        model.setCustomCover(TestImages.png(width: 8, height: 8))
        #expect(model.coverSource == .custom)
        model.resetCover()
        #expect(model.coverSource == .generated)
    }

    @Test func generatedCoverFollowsTitle() async {
        let (model, _, generator) = makeModel()
        await model.open(bookURL)
        await model.waitForSizeComputation()
        let initialRequests = generator.requests.count

        model.title = "N"
        model.title = "Ne"
        model.title = "New Title"
        #expect(generator.requests.count == initialRequests)
        await model.waitForSizeComputation()
        #expect(generator.requests.count == initialRequests + 1)
        #expect(generator.requests.last?.title == "New Title")
        #expect(model.cover?.data == Data("New Title".utf8))

        model.author = "Someone"
        await model.waitForSizeComputation()
        #expect(generator.requests.last?.title == "New Title")
        #expect(generator.requests.last?.author == "Someone")

        model.setCustomCover(TestImages.png(width: 8, height: 8))
        await model.waitForSizeComputation()
        let count = generator.requests.count
        model.title = "Ignored"
        await model.waitForSizeComputation()
        #expect(generator.requests.count == count)
    }

    @Test func measuredCoverMatchesRegeneratedCover() async {
        let (model, converter, _) = makeModel()
        await model.open(bookURL)
        model.title = "Measured"
        await model.waitForSizeComputation()
        #expect(converter.recorded.writtenCovers.last??.data == Data("Measured".utf8))
    }

    @Test func exportFlushesPendingCoverRegeneration() async throws {
        let (model, converter, _) = makeModel()
        await model.open(bookURL)
        model.title = "Exported"
        _ = try model.exportData()
        #expect(converter.recorded.writtenCovers.last??.data == Data("Exported".utf8))
        #expect(model.cover?.data == Data("Exported".utf8))
    }

    @Test func fileCoverDoesNotRegenerateOnTitleChange() async {
        let (model, _, generator) = makeModel(cover: sourceCover)
        await model.open(bookURL)
        model.title = "Other"
        await model.waitForSizeComputation()
        #expect(generator.requests.isEmpty)
        #expect(model.cover == sourceCover)
    }

    @Test func sizeComputedAfterEdits() async {
        let (model, converter, _) = makeModel(cover: sourceCover)
        await model.open(bookURL)
        await model.waitForSizeComputation()
        #expect(model.bookSize == FakeConverter.epubSize)
        #expect(converter.recorded.writtenFormats == [.epub])

        model.outputFormat = .fb2
        #expect(model.bookSize == nil)
        #expect(model.sizeStatus == .computing)
        await model.waitForSizeComputation()
        #expect(model.sizeStatus == .ready(FakeConverter.fb2Size))
        #expect(model.bookSize == FakeConverter.fb2Size)
        #expect(converter.recorded.writtenFormats.last == .fb2)
        #expect(converter.recorded.writtenCovers.last == sourceCover)
    }

    @Test func failedWriteReportsFailedSize() async {
        let (model, converter, _) = makeModel(cover: sourceCover)
        converter.setFailsWrites(true)
        await model.open(bookURL)
        await model.waitForSizeComputation()
        #expect(model.sizeStatus == .failed)
        #expect(model.bookSize == nil)

        converter.setFailsWrites(false)
        model.title = "Retry"
        await model.waitForSizeComputation()
        #expect(model.sizeStatus == .ready(FakeConverter.epubSize))
    }

    @Test func supersededSlowWriteNeverLandsAndWritesAreSerialized() async {
        let converter = GatedConverter(gatesWrites: true)
        let model = ConverterViewModel(makeConverter: { _ in converter }, coverGenerator: FakeCoverGenerator())
        await model.open(URL(filePath: "/tmp/Slow.txt"))
        await waitUntil { converter.writeState.started == 1 }
        #expect(converter.writeState.started == 1)

        model.title = "Changed"
        try? await Task.sleep(for: .milliseconds(500))
        #expect(converter.writeState.started == 1, "a new write must wait for the superseded one")

        converter.releaseNextWrite()
        await waitUntil { converter.writeState.started == 2 }
        #expect(converter.writeState.started == 2)
        #expect(model.sizeStatus == .computing, "the superseded write's size must not land")

        converter.releaseNextWrite()
        await model.waitForSizeComputation()
        #expect(model.sizeStatus == .ready(1001))
        #expect(converter.writeState.maxInFlight == 1)
    }

    @Test func secondOpenWinsOverSlowFirstImport() async {
        let slowURL = URL(filePath: "/tmp/Slow.txt")
        let fastURL = URL(filePath: "/tmp/Fast.txt")
        let converter = GatedConverter(slowURL: slowURL)
        let model = ConverterViewModel(makeConverter: { _ in converter }, coverGenerator: FakeCoverGenerator())

        let first = Task { await model.open(slowURL) }
        await waitUntil { converter.startedImports.contains(slowURL) }
        await model.open(fastURL)
        #expect(model.title == "Fast")

        converter.releaseSlowImport()
        await first.value
        #expect(model.title == "Fast")
        #expect(model.state == .loaded)
    }

    @Test func rapidEditsAreDebouncedIntoOneWrite() async {
        let (model, converter, _) = makeModel(cover: sourceCover)
        await model.open(bookURL)
        await model.waitForSizeComputation()
        let writes = converter.recorded.writtenFormats.count

        model.title = "A"
        model.title = "AB"
        model.language = "en"
        await model.waitForSizeComputation()
        #expect(converter.recorded.writtenFormats.count == writes + 1)
        #expect(converter.recorded.writtenDocuments.last?.metadata == BookMetadata(title: "AB", author: "Лев Толстой", language: "en"))
    }

    @Test func exportUsesEditedMetadataAndCover() async throws {
        let (model, converter, _) = makeModel(cover: sourceCover)
        await model.open(bookURL)
        model.title = "Edited"
        model.author = "Author"
        model.language = "en"
        model.outputFormat = .fb2

        let data = try model.exportData()
        #expect(data.count == FakeConverter.fb2Size)
        #expect(converter.recorded.writtenFormats.last == .fb2)
        #expect(converter.recorded.writtenDocuments.last?.metadata == BookMetadata(title: "Edited", author: "Author", language: "en"))
        #expect(converter.recorded.writtenCovers.last == sourceCover)
    }

    @Test func blankTitleFallsBackToOriginalThenFileName() async throws {
        let (model, converter, _) = makeModel()
        await model.open(bookURL)
        model.title = "  "
        model.author = "  Лев Толстой "
        _ = try model.exportData()
        #expect(converter.recorded.writtenDocuments.last?.metadata.title == "Война и мир")
        #expect(converter.recorded.writtenDocuments.last?.metadata.author == "Лев Толстой")

        let (untitled, untitledConverter, _) = makeModel(originalTitle: " ")
        await untitled.open(bookURL)
        untitled.title = ""
        _ = try untitled.exportData()
        #expect(untitledConverter.recorded.writtenDocuments.last?.metadata.title == "My Book")

        model.title = "  Edited  "
        _ = try model.exportData()
        #expect(converter.recorded.writtenDocuments.last?.metadata.title == "Edited")
    }

    @Test func exportTitleMatchesWrittenTitle() async throws {
        let (model, converter, _) = makeModel()
        await model.open(bookURL)
        model.title = " Edited "
        #expect(model.exportTitle == "Edited")
        model.title = ""
        #expect(model.exportTitle == "Война и мир")
        _ = try model.exportData()
        #expect(converter.recorded.writtenDocuments.last?.metadata.title == model.exportTitle)
    }

    @Test func blankTitleExportsNonEmptyTitleWithRealConverter() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "book.txt")
        try Data("Chapter 1\n\nSome text of the book.".utf8).write(to: url)

        let model = ConverterViewModel(coverGenerator: FakeCoverGenerator())
        await model.open(url)
        model.title = "  "
        for format in OutputFormat.allCases {
            model.outputFormat = format
            let output = dir.appending(path: "out.\(format.fileExtension)")
            try model.exportData().write(to: output)
            let reimported = try await BookConverter().importBook(from: output, context: ImportContext())
            #expect(reimported.document.metadata.title == "book")
        }
    }

    @Test func unsupportedFileKeepsLoadedBook() async {
        let imageURL = URL(filePath: "/tmp/ConverterViewModelTests/cover.jpg")
        let (model, converter, _) = makeModel()
        converter.setUnsupported([imageURL])
        await model.open(bookURL)
        model.title = "Kept edit"
        let document = model.document

        await model.open(imageURL)
        #expect(model.state == .loaded)
        #expect(model.document == document)
        #expect(model.title == "Kept edit")
        #expect(model.lastError == .unsupportedFormat)
        #expect(converter.recorded.importedURLs == [bookURL])

        await model.open(bookURL)
        #expect(model.lastError == nil)
        #expect(converter.recorded.importedURLs == [bookURL, bookURL])
    }

    @Test func unsupportedFileWithoutBookFails() async {
        let imageURL = URL(filePath: "/tmp/ConverterViewModelTests/cover.jpg")
        let (model, converter, _) = makeModel()
        converter.setUnsupported([imageURL])
        await model.open(imageURL)
        #expect(model.state == .failed(.unsupportedFormat))
        #expect(model.document == nil)
    }

    @Test func suggestedFileNameSanitized() async {
        let (model, _, _) = makeModel()
        await model.open(bookURL)
        model.title = "A/B: C"
        #expect(model.suggestedFileName == "A B C.epub")

        model.title = " \"x\" <y>|*?%\\ "
        model.outputFormat = .fb2
        #expect(model.suggestedFileName == "x y.fb2")

        model.title = " /:: "
        #expect(model.suggestedFileName == "Book.fb2")
    }

    @Test func grantFolderAccessReimportsWithContext() async {
        let folder = URL(filePath: "/tmp/ConverterViewModelTests", directoryHint: .isDirectory)
        let (model, converter, _) = makeModel(warnings: [.imagesNeedFolderAccess(folder: folder)])
        await model.open(bookURL)
        model.title = "Kept edit"

        await model.grantFolderAccess(folder)
        #expect(converter.recorded.importedURLs == [bookURL, bookURL])
        #expect(converter.recorded.contexts.last?.accessibleFolder == folder)
        #expect(model.state == .loaded)
        #expect(model.title == "Kept edit")
    }

    @Test func failedGrantFolderAccessKeepsBook() async {
        let (model, converter, _) = makeModel()
        await model.open(bookURL)
        model.title = "Kept edit"
        let document = model.document
        #expect(model.lastError == nil)

        converter.setFailsImports(true)
        await model.grantFolderAccess(URL(filePath: "/tmp", directoryHint: .isDirectory))
        #expect(model.state == .loaded)
        #expect(model.document == document)
        #expect(model.title == "Kept edit")
        #expect(model.lastError == .unreadable(CocoaError(.fileReadUnknown).localizedDescription))

        converter.setFailsImports(false)
        await model.grantFolderAccess(URL(filePath: "/tmp", directoryHint: .isDirectory))
        #expect(model.lastError == nil)
    }

    @Test func supersededGrantAfterFailedGrantLeavesNoStaleError() async {
        let failing = URL(filePath: "/tmp/failing", directoryHint: .isDirectory)
        let first = URL(filePath: "/tmp/first", directoryHint: .isDirectory)
        let second = URL(filePath: "/tmp/second", directoryHint: .isDirectory)
        let converter = GatedConverter(gatedFolders: [first, second], failingFolder: failing)
        let model = ConverterViewModel(makeConverter: { _ in converter }, coverGenerator: FakeCoverGenerator())
        await model.open(bookURL)

        await model.grantFolderAccess(failing)
        #expect(model.lastError == .unreadable("denied"))

        let superseded = Task { await model.grantFolderAccess(first) }
        await waitUntil { converter.startedFolders.contains(first) }
        let latest = Task { await model.grantFolderAccess(second) }
        await waitUntil { converter.startedFolders.contains(second) }

        converter.releaseImports(withFolder: first)
        await superseded.value
        #expect(model.lastError == nil, "the superseded grant must not leave the earlier failure behind")

        converter.releaseImports(withFolder: second)
        await latest.value
        #expect(model.lastError == nil)
        #expect(model.state == .loaded)
    }

    @Test func factoryReceivesOpenTime() async {
        let openTime = Date(timeIntervalSince1970: 1_000_000)
        let converter = FakeConverter(result: .success(ImportResult(document: document())))
        let dates = DateBox()
        let model = ConverterViewModel(
            makeConverter: { date in dates.append(date); return converter },
            coverGenerator: FakeCoverGenerator(),
            now: { openTime }
        )
        await model.open(bookURL)
        #expect(dates.values == [openTime])
    }

    @Test func exportMatchesReportedSizeWithRealConverter() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "book.txt")
        try Data("Chapter 1\n\nSome text of the book.\n\nChapter 2\n\nMore text here.".utf8).write(to: url)

        let model = ConverterViewModel(coverGenerator: FakeCoverGenerator())
        await model.open(url)
        #expect(model.state == .loaded)
        for format in OutputFormat.allCases {
            model.outputFormat = format
            await model.waitForSizeComputation()
            let size = try #require(model.bookSize)
            try await Task.sleep(for: .milliseconds(1100))
            #expect(try model.exportData().count == size)
        }
    }

    @Test func realGeneratorProducesPortraitJPEG() throws {
        let cover = try #require(CoverGenerator().makeCover(title: "一个很长的书名 — with a very long mixed title that has to wrap", author: "مؤلف"))
        #expect(cover.id == "cover")
        #expect(cover.contentType == .jpeg)
        #expect(cover.pixelWidth == 1200 && cover.pixelHeight == 1600)
    }
}
