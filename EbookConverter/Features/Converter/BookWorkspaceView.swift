import SwiftUI
import AppKit
import ConverterFeature
import EbookCore

/// Loaded-book screen: table of contents, chapter preview and the inspector.
struct BookWorkspaceView: View {
    @Bindable var viewModel: ConverterViewModel

    @State private var isImporterPresented = false

    var body: some View {
        NavigationSplitView {
            ChapterSidebar(chapters: viewModel.document?.chapters ?? [], selection: $viewModel.selectedChapterID)
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 360)
        } detail: {
            VStack(spacing: 0) {
                WarningBanner(warnings: viewModel.warnings)
                if let document = viewModel.document,
                   let id = viewModel.selectedChapterID,
                   let chapter = document.chapter(withID: id) {
                    ChapterPreview(chapter: chapter, isRightToLeft: isRightToLeft)
                        // A re-imported book may reuse image IDs for other data; start with a fresh cache.
                        .id(document.identifier)
                } else {
                    Spacer()
                }
            }
        }
        .inspector(isPresented: .constant(true)) {
            InspectorView(viewModel: viewModel)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
        }
        .toolbar {
            Button(.openFile, systemImage: "folder") {
                isImporterPresented = true
            }
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: SupportedTypes.inputs) { result in
            if case .success(let url) = result {
                open(url)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            open(url)
            return true
        }
        .frame(minWidth: ConverterLayout.workspaceMinSize.width, minHeight: ConverterLayout.workspaceMinSize.height)
        .onAppear {
            WindowGrowth.grow(NSApp.keyWindow ?? NSApp.mainWindow, toContentSize: ConverterLayout.workspaceIdealSize)
        }
    }

    /// Direction of the edited language, matching the `dir` the exported EPUB gets.
    private var isRightToLeft: Bool {
        BookMetadata(title: "", author: "", language: viewModel.language).isRightToLeft
    }

    private func open(_ url: URL) {
        Task { await viewModel.open(url) }
    }
}

// The sample-book preview support is compiled in Debug only.
#if DEBUG
#Preview(traits: .modifier(LoadedBookPreview())) {
    LoadedBookPreviewHost { viewModel in
        BookWorkspaceView(viewModel: viewModel)
    }
}

#Preview("Chapter with image", traits: .modifier(LoadedBookPreview())) {
    LoadedBookPreviewHost { viewModel in
        BookWorkspaceView(viewModel: viewModel)
            .onAppear {
                viewModel.selectedChapterID = viewModel.document?.leafChapters.dropFirst().first?.id
            }
    }
}
#endif
