public enum ImportError: Error, Sendable, Hashable {
    case unsupportedFormat
    case emptyDocument
    case pdfHasNoTextLayer
    case pdfLocked
    case unreadable(String)
}
