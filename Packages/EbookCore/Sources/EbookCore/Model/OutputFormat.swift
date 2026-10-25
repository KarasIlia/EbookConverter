import UniformTypeIdentifiers

public enum OutputFormat: String, Sendable, Hashable, CaseIterable {
    case epub, fb2

    public var fileExtension: String { rawValue }

    public var contentType: UTType {
        switch self {
        case .epub: .epub
        case .fb2: UTType(exportedAs: "ru.fictionbook.fb2", conformingTo: .xml)
        }
    }
}
