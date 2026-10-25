import SwiftUI
import AppKit
import ConverterFeature
import EbookCore

/// Right column: cover, editable metadata, output format, size and the Convert button.
struct InspectorView: View {
    @Bindable var viewModel: ConverterViewModel

    @State private var exportedFile: ExportedBookFile?
    @State private var isExporterPresented = false
    @State private var savedURL: URL?
    @State private var isExportFailed = false

    var body: some View {
        Form {
            Section {
                // Replaced by the cover well in Task 19.
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .overlay {
                        Label {
                            Text(.coverPlaceholder)
                        } icon: {
                            Image(systemName: "book.closed")
                        }
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 160)
                    .frame(maxWidth: .infinity)
            }

            Section {
                TextField(text: $viewModel.title) {
                    Text(.fieldTitle)
                }
                TextField(text: $viewModel.author) {
                    Text(.fieldAuthor)
                }
                Picker(selection: languageSelection) {
                    ForEach(LanguageOption.options(bookLanguage: viewModel.document?.metadata.language ?? "")) { option in
                        if let name = option.name {
                            Text(name).tag(option.code)
                        } else {
                            Text(.languageUnknown).tag(option.code)
                        }
                    }
                } label: {
                    Text(.fieldLanguage)
                }
            }

            Section {
                Picker(selection: $viewModel.outputFormat) {
                    ForEach(OutputFormat.allCases, id: \.self) { format in
                        Text(verbatim: format.rawValue.uppercased()).tag(format)
                    }
                } label: {
                    Text(.fieldFormat)
                }
                .pickerStyle(.segmented)

                BookSizeLabel(status: viewModel.sizeStatus)
            }

            Section {
                Button(action: export) {
                    Text(.convert)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(viewModel.sizeStatus == .failed)

                if let savedURL {
                    LabeledContent {
                        Button(.showInFinder, systemImage: "folder") {
                            NSWorkspace.shared.activateFileViewerSelecting([savedURL])
                        }
                    } label: {
                        Label {
                            Text(.savedConfirmation)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportedFile,
            contentType: viewModel.outputFormat.contentType,
            defaultFilename: viewModel.suggestedFileName
        ) { result in
            exportedFile = nil
            switch result {
            case .success(let url): savedURL = url
            case .failure(let error):
                isExportFailed = (error as? CocoaError)?.code != .userCancelled
            }
        }
        .alert(Text(.exportFailed), isPresented: $isExportFailed) {}
        // The confirmation is about the saved file; any edit makes the next export a different book.
        .onChange(of: viewModel.title) { savedURL = nil }
        .onChange(of: viewModel.author) { savedURL = nil }
        .onChange(of: viewModel.language) { savedURL = nil }
        .onChange(of: viewModel.outputFormat) { savedURL = nil }
        .onChange(of: viewModel.cover) { savedURL = nil }
    }

    /// The edited language, with an empty tag shown as undetermined.
    private var languageSelection: Binding<String> {
        Binding {
            LanguageOption.normalized(viewModel.language)
        } set: { code in
            viewModel.language = code
        }
    }

    private func export() {
        savedURL = nil
        do {
            exportedFile = ExportedBookFile(data: try viewModel.exportData())
            isExporterPresented = true
        } catch {
            isExportFailed = true
        }
    }
}
