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
    ].compactMap(\.self)

    /// Image types accepted as a custom cover, by drag and drop or in the file importer.
    static let coverImages: [UTType] = [.jpeg, .png, .heic, .tiff]
}
