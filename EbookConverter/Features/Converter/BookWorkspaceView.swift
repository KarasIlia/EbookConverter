import SwiftUI
import AppKit
import ConverterFeature
import EbookCore

/// Loaded-book screen: table of contents, chapter preview and the inspector.
struct BookWorkspaceView: View {
    @Bindable var viewModel: ConverterViewModel

    @State private var isImporterPresented = false
    /// Failure of the last folder-access re-import, shown in an alert; the loaded book stays.
    @State private var folderAccessError: ImportError?

    var body: some View {
        NavigationSplitView {
            ChapterSidebar(chapters: viewModel.document?.chapters ?? [], selection: $viewModel.selectedChapterID)
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 360)
        } detail: {
            VStack(spacing: 0) {
                WarningBanner(warnings: viewModel.warnings)
                if let folder = imagesFolder {
                    FolderAccessBanner(folder: folder, onGrant: grantFolderAccess)
                }
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
        .alert(
            Text(.folderAccessFailed),
            isPresented: Binding { folderAccessError != nil } set: { if !$0 { folderAccessError = nil } },
            presenting: folderAccessError
        ) { _ in
        } message: { error in
            Text(ConverterRootView.message(for: error))
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

    /// Folder of images the sandbox could not read, if the import reported one.
    private var imagesFolder: URL? {
        viewModel.warnings.lazy.compactMap { warning in
            if case .imagesNeedFolderAccess(let folder) = warning { folder } else { nil }
        }.first
    }

    private func open(_ url: URL) {
        Task { await viewModel.open(url) }
    }

    /// Re-imports the book with access to `folder`; on success the warning (and banner) is replaced.
    private func grantFolderAccess(_ folder: URL) {
        Task {
            await viewModel.grantFolderAccess(folder)
            folderAccessError = viewModel.lastError
        }
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
