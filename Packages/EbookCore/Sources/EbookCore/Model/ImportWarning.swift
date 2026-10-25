import Foundation

public enum ImportWarning: Sendable, Hashable {
    case noChaptersFound
    case languageUndetermined
    case imagesNeedFolderAccess(folder: URL)
    case imagesUnavailable(count: Int)
    case remoteImagesSkipped(count: Int)
}
