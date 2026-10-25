#if DEBUG
import Foundation
import EbookCore
import ConverterFeature

/// Preview-only converter: "imports" a small fixed book and writes placeholder bytes.
struct PreviewBookConverter: BookConverting {
    func sourceFormat(of url: URL) throws -> SourceFormat {
        .txt
    }

    func importBook(from url: URL, context: ImportContext) async throws -> ImportResult {
        let image = await CoverGenerator().makeCover(title: "Illustration", author: "Preview").map(Block.image)
        let chapters = [
            Chapter(title: "Preface", blocks: [
                .heading(level: 1, runs: [InlineRun("Preface")]),
                .paragraph([
                    InlineRun("This is a "), InlineRun("preview", bold: true), InlineRun(" of a converted book with "),
                    InlineRun("italic", italic: true), InlineRun(" text."),
                ]),
            ]),
            Chapter(title: "Part One", children: [
                Chapter(title: "Chapter 1", blocks: [
                    .heading(level: 2, runs: [InlineRun("Chapter 1")]),
                    .paragraph([InlineRun(String(repeating: "Lorem ipsum dolor sit amet. ", count: 40))]),
                ] + (image.map { [$0] } ?? []) + [
                    .heading(level: 3, runs: [InlineRun("A section")]),
                    .paragraph([InlineRun(String(repeating: "Consectetur adipiscing elit. ", count: 30))]),
                ]),
                Chapter(blocks: [.paragraph([InlineRun("A chapter without a title.")])]),
            ]),
        ]
        let document = BookDocument(
            metadata: BookMetadata(title: "Sample Book", author: "Jane Doe", language: "en"),
            chapters: chapters
        )
        return ImportResult(document: document, warnings: [.remoteImagesSkipped(count: 2)])
    }

    func write(_ document: BookDocument, cover: ImageAsset?, as format: OutputFormat) throws -> Data {
        Data(count: format == .epub ? 245_760 : 312_320)
    }
}
#endif
