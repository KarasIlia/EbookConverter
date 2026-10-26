import Foundation
import UniformTypeIdentifiers

/// File types the converter can open.
enum SupportedTypes {
    /// Input types for the file importer; types unknown to the system are skipped.
    static let inputs: [UTType] = [
        .plainText,
        UTType("net.daringfireball.markdown"),
        .rtf,
        UTType("com.microsoft.word.doc"),
        UTType("org.openxmlformats.wordprocessingml.document"),
        .html,
        .pdf,
        .epub,
        UTType("ru.fictionbook.fb2"),
    ].compactMap(\.self) + extensionTypes

    /// Types the system currently maps our file extensions to. Another app may declare its own type for an
    /// extension (e.g. a browser declaring `public.fb2` for `.fb2`), and then files carry that type instead of ours.
    private static let extensionTypes: [UTType] = [
        "txt", "text", "md", "markdown", "rtf", "doc", "docx", "htm", "html", "xhtml", "pdf", "epub", "fb2",
    ].compactMap { UTType(filenameExtension: $0) }

    /// Image types accepted as a custom cover, by drag and drop or in the file importer.
    static let coverImages: [UTType] = [.jpeg, .png, .heic, .tiff, .webP]

    /// `true` if the file at `url` has one of `types`, judged by the file system's content type
    /// (or, failing that, by the file name extension).
    static func file(_ url: URL, isOneOf types: [UTType]) -> Bool {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        guard let type else { return false }
        return types.contains(where: type.conforms(to:))
    }
}
