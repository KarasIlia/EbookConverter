import SwiftUI

/// Banner for a book whose images sit in a folder the sandbox cannot read yet:
/// asks the user to grant access to that folder so the images are kept.
struct FolderAccessBanner: View {
    /// Folder the images are in; the folder picker opens there.
    let folder: URL
    /// Called with the folder the user granted access to.
    let onGrant: @MainActor (URL) -> Void

    @State private var isImporterPresented = false

    var body: some View {
        HStack {
            Label {
                Text(.folderAccessMessage)
            } icon: {
                Image(systemName: "photo.badge.exclamationmark")
                    .foregroundStyle(.tint)
            }
            Spacer()
            Button(.grantFolderAccess, systemImage: "folder.badge.plus") {
                isImporterPresented = true
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.bar)
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                onGrant(url)
            }
        }
        .fileDialogDefaultDirectory(folder)
    }
}

#Preview {
    FolderAccessBanner(folder: URL(filePath: "/tmp")) { _ in }
        .frame(width: 640)
}
