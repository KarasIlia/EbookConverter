import UniformTypeIdentifiers

public enum OutputFormat: String, Sendable, Hashable, CaseIterable {
    case epub, fb2

    public var fileExtension: String { rawValue }

    /// FB2 is declared by the app as an imported type (we do not own it), so it is `importedAs` here too.
    public var contentType: UTType {
        switch self {
        case .epub: .epub
        case .fb2: UTType(importedAs: "ru.fictionbook.fb2", conformingTo: .xml)
        }
    }
}
