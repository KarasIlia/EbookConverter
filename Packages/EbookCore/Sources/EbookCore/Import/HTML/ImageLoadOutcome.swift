import Foundation

/// Result of trying to load an image referenced from a source document.
public enum ImageLoadOutcome: Sendable {
    case loaded(ImageAsset)
    /// The file at the given location could not be read and the user has not granted access to a folder yet.
    case needsFolderAccess(URL)
    /// A `http(s)` reference; the app never fetches from the network.
    case remote
    case missing
}
