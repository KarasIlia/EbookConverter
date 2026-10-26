/// Maps a detected format to the importer that handles it.
public enum ImporterRegistry {
    public static func importer(for format: SourceFormat) -> any BookImporter {
        switch format {
        case .txt: TXTImporter()
        case .markdown: MarkdownImporter()
        case .rtf, .doc, .docx, .html: AttributedTextImporter()
        case .pdf: PDFImporter()
        case .epub: EPUBImporter()
        case .fb2: FB2Importer()
        }
    }
}
