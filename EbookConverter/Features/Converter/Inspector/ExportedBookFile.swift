import SwiftUI
import UniformTypeIdentifiers
import EbookCore

/// The converted book handed to `fileExporter`.
struct ExportedBookFile: FileDocument {
    static let readableContentTypes: [UTType] = OutputFormat.allCases.map(\.contentType)
    static let writableContentTypes: [UTType] = OutputFormat.allCases.map(\.contentType)

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
