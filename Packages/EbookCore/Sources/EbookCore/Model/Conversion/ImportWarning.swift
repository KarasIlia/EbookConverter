import Foundation

public enum ImportWarning: Sendable, Hashable {
    case noChaptersFound
    case languageUndetermined
    case imagesNeedFolderAccess(folder: URL)
    case imagesUnavailable(count: Int)
    case remoteImagesSkipped(count: Int)
    /// Content files that could not be read, or whose markup was cut short by a parse error.
    case contentPartiallyUnreadable(count: Int)
}
