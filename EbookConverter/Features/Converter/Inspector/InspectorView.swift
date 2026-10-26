import SwiftUI
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
                CoverWell(
                    cover: viewModel.cover,
                    source: viewModel.coverSource,
                    onSetCover: viewModel.setCustomCover,
                    onReset: viewModel.resetCover
                )
            }

            Section {
                MetadataTextField(label: .fieldTitle, text: $viewModel.title)
                MetadataTextField(label: .fieldAuthor, text: $viewModel.author)
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
            } header: {
                Text(.bookDetails)
            } footer: {
                Text(.languageHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(selection: $viewModel.outputFormat) {
                    ForEach(OutputFormat.allCases, id: \.self) { format in
                        Text(verbatim: format.rawValue.uppercased())
                            .tag(format)
                            .selectionDisabled(!viewModel.availableOutputFormats.contains(format))
                    }
                } label: {
                    Text(.fieldFormat)
                }
                .pickerStyle(.segmented)

                if let sameFormat = viewModel.sourceFormat?.sameOutputFormat {
                    Text(.formatSameAsSource(sameFormat.rawValue.uppercased()))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                BookSizeLabel(status: viewModel.sizeStatus)
            }

        }
        .formStyle(.grouped)
        // The primary action stays visible however long the form gets.
        .safeAreaInset(edge: .bottom) {
            ExportBar(
                isDisabled: viewModel.sizeStatus == .failed,
                savedURL: savedURL,
                onExport: export
            )
        }
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
