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
        failure: (any Error)? = nil
    ) -> (ConverterViewModel, FakeConverter, FakeCoverGenerator) {
        let result: Result<ImportResult, any Error> = if let failure {
            .failure(failure)
        } else {
            .success(ImportResult(document: document(), sourceCover: cover, warnings: warnings))
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

        model.setCustomCover(TestImages.png(width: 30, height: 40))
        #expect(model.coverSource == .custom)
        let custom = try #require(model.cover)
        #expect(custom.id == "cover")
        #expect(custom.contentType == .png)
        #expect(custom.pixelWidth == 30 && custom.pixelHeight == 40)

        model.setCustomCover(Data("not an image".utf8))
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

        model.title = "New Title"
        #expect(generator.requests.last?.title == "New Title")
        #expect(model.cover?.data == Data("New Title".utf8))

        model.author = "Someone"
        #expect(generator.requests.last?.title == "New Title")
        #expect(generator.requests.last?.author == "Someone")

        model.setCustomCover(TestImages.png(width: 8, height: 8))
        let count = generator.requests.count
        model.title = "Ignored"
        #expect(generator.requests.count == count)
    }

    @Test func fileCoverDoesNotRegenerateOnTitleChange() async {
        let (model, _, generator) = makeModel(cover: sourceCover)
        await model.open(bookURL)
        model.title = "Other"
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
        await model.waitForSizeComputation()
        #expect(model.bookSize == FakeConverter.fb2Size)
        #expect(converter.recorded.writtenFormats.last == .fb2)
        #expect(converter.recorded.writtenCovers.last == sourceCover)
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
