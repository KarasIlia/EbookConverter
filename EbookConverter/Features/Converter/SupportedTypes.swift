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
}
