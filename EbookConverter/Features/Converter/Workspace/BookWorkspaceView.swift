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
    /// Failure of opening another file over the loaded book, shown in an alert; the loaded book stays.
    @State private var openError: ImportError?
    @State private var isCoverImageUnreadable = false
    /// Width of the preview column; the file name in the toolbar is truncated to fit it.
    @State private var detailWidth: CGFloat = 0
    /// The user can hide the inspector (button or by dragging it closed) and bring it back with the toolbar button.
    @State private var isInspectorPresented = true

    /// "FB2 file" for the opened book, shown under the file name in the window title.
    private var sourceSubtitle: Text {
        guard let format = viewModel.sourceFormat else { return Text(verbatim: "") }
        return Text(.sourceFormatSubtitle(format.displayName))
    }

    var body: some View {
        NavigationSplitView {
            ChapterSidebar(
                chapters: viewModel.document?.chapters ?? [],
                bookTitle: viewModel.exportTitle,
                selection: $viewModel.selectedChapterID
            )
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
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { detailWidth = $0 }
        }
        .inspector(isPresented: $isInspectorPresented) {
            InspectorView(viewModel: viewModel)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(.openFile, systemImage: "folder") {
                    isImporterPresented = true
                }
                Button(.toggleInspector, systemImage: "sidebar.trailing") {
                    isInspectorPresented.toggle()
                }
                .help(Text(.toggleInspector))
            }
        }
        .navigationTitle(TitleFitting.fitted(
            viewModel.sourceFileName ?? "", toWidth: detailWidth - ConverterLayout.titleHorizontalInset
        ))
        .navigationSubtitle(sourceSubtitle)
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: SupportedTypes.inputs) { result in
            if case .success(let url) = result {
                open(url)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            // An image dropped anywhere on the book becomes its cover rather than replacing the book.
            if SupportedTypes.file(url, isOneOf: SupportedTypes.coverImages) {
                setCover(from: url)
                return true
            }
            guard SupportedTypes.file(url, isOneOf: SupportedTypes.inputs) else { return false }
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
        .alert(
            Text(.openFileFailed),
            isPresented: Binding { openError != nil } set: { if !$0 { openError = nil } },
            presenting: openError
        ) { _ in
        } message: { error in
            Text(ConverterRootView.message(for: error))
        }
        .alert(Text(.coverImageUnreadable), isPresented: $isCoverImageUnreadable) {}
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

    /// Opens `url` in place of the loaded book; if the file cannot be imported at all the book stays and an alert explains why.
    private func open(_ url: URL) {
        Task {
            await viewModel.open(url)
            openError = viewModel.state == .loaded ? viewModel.lastError : nil
        }
    }

    private func setCover(from url: URL) {
        Task {
            guard let data = await CoverDropItem.imageData(at: url), viewModel.setCustomCover(data) else {
                isCoverImageUnreadable = true
                return
            }
        }
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
