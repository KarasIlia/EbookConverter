import Foundation

public struct ImportContext: Sendable {
    /// Folder the user granted access to, used to resolve images referenced by relative path.
    public var accessibleFolder: URL?

    public init(accessibleFolder: URL? = nil) {
        self.accessibleFolder = accessibleFolder
    }
}
