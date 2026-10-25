import SwiftUI
import EbookCore

/// Non-blocking import warnings shown above the preview.
struct WarningBanner: View {
    let warnings: [ImportWarning]

    var body: some View {
        let messages = warnings.compactMap(Self.message(for:))
        if !messages.isEmpty {
            VStack(alignment: .leading) {
                ForEach(messages.enumerated(), id: \.offset) { _, message in
                    Label {
                        Text(message)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.bar)
        }
    }

    /// User-facing text for a warning; `nil` for warnings handled elsewhere (folder access, Task 19).
    static func message(for warning: ImportWarning) -> LocalizedStringResource? {
        switch warning {
        case .noChaptersFound: .warningNoChapters
        case .languageUndetermined: .warningLanguageUnknown
        case .remoteImagesSkipped(let count): .warningRemoteImages(count)
        case .imagesUnavailable(let count): .warningImagesUnavailable(count)
        case .contentPartiallyUnreadable(let count): .warningContentPartiallyUnreadable(count)
        case .imagesNeedFolderAccess: nil
        }
    }
}

#Preview {
    WarningBanner(warnings: [
        .noChaptersFound,
        .languageUndetermined,
        .remoteImagesSkipped(count: 3),
        .imagesUnavailable(count: 2),
        .contentPartiallyUnreadable(count: 1),
    ])
}
