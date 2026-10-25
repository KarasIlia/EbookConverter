import Foundation

/// Entry point of the core: detects the format, imports a file and writes EPUB/FB2 output.
public struct BookConverter: Sendable {
    /// Formats whose importers do not detect covers themselves.
    private static let coverDetectedFormats: Set<SourceFormat> = [.txt, .markdown, .rtf, .doc, .docx, .html]

    private let fixedDate: Date?

    /// - Parameter fixedDate: Timestamp written into output files. Pass a fixed value so repeated
    ///   writes of the same document are byte-identical (stable size estimates); `nil` uses the current date.
    public init(fixedDate: Date? = nil) {
        self.fixedDate = fixedDate
    }

    public func importBook(from url: URL, context: ImportContext) async throws -> ImportResult {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw ImportError.unreadable(error.localizedDescription) }
        guard !data.isEmpty else { throw ImportError.emptyDocument }
        guard let format = FormatSniffer.format(of: data, fileExtension: url.pathExtension) else {
            throw ImportError.unsupportedFormat
        }
        var result = try await ImporterRegistry.importer(for: format).importBook(from: url, context: context)
        if result.sourceCover == nil, Self.coverDetectedFormats.contains(format) {
            result.sourceCover = CoverDetector.extractCover(from: &result.document)
        }
        return result
    }

    public func write(_ document: BookDocument, cover: ImageAsset?, as format: OutputFormat) throws -> Data {
        let date = fixedDate ?? .now
        let writer: any BookWriter = switch format {
        case .epub: EPUBWriter(modified: date)
        case .fb2: FB2Writer(date: date)
        }
        return try writer.write(document, cover: cover)
    }
}
