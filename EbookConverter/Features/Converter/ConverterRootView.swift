import SwiftUI
import ConverterFeature
import EbookCore

/// Top-level converter screen: switches between the drop zone, import progress and the loaded book.
struct ConverterRootView: View {
    let viewModel: ConverterViewModel

    var body: some View {
        Group {
            switch viewModel.state {
            case .empty:
                DropZoneView(errorMessage: nil, onOpen: open)
            case .failed(let error):
                DropZoneView(errorMessage: Self.message(for: error), onOpen: open)
            case .loading(let fileName):
                ProgressView {
                    Text(.openingFile(fileName))
                }
                .frame(minWidth: 480, minHeight: 360)
            case .loaded:
                // Replaced by the three-column book editor in Task 18.
                Text(.bookLoaded)
                    .frame(minWidth: 480, minHeight: 360)
            }
        }
        .containerBackground(.thinMaterial, for: .window)
    }

    private func open(_ url: URL) {
        Task { await viewModel.open(url) }
    }

    /// User-facing text for an import failure.
    static func message(for error: ImportError) -> LocalizedStringResource {
        switch error {
        case .unsupportedFormat: .errorUnsupportedFormat
        case .emptyDocument: .errorEmptyDocument
        case .pdfHasNoTextLayer: .errorPdfNoText
        case .pdfLocked: .errorPdfLocked
        case .unreadable: .errorUnreadable
        }
    }
}

#Preview {
    ConverterRootView(viewModel: ConverterViewModel())
}
