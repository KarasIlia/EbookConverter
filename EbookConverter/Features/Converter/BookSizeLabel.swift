import SwiftUI
import ConverterFeature

/// "Book size" row: a spinner while the output is measured, then its exact size.
struct BookSizeLabel: View {
    let status: BookSizeStatus

    var body: some View {
        LabeledContent {
            switch status {
            case .computing:
                ProgressView()
                    .controlSize(.small)
            case .ready(let size):
                Text(size.formatted(.byteCount(style: .file)))
                    .monospacedDigit()
            case .failed:
                Text(.sizeUnavailable)
                    .foregroundStyle(.red)
            }
        } label: {
            Text(.bookSize)
        }
    }
}

#Preview {
    Form {
        BookSizeLabel(status: .computing)
        BookSizeLabel(status: .ready(1_234_567))
        BookSizeLabel(status: .failed)
    }
    .formStyle(.grouped)
}
