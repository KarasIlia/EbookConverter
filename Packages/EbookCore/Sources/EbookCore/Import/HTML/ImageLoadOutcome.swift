/// Result of trying to load an image referenced from a source document.
public enum ImageLoadOutcome: Sendable {
    case loaded(ImageAsset)
    /// The file could not be read and the user has not granted access to its folder yet.
    case needsFolderAccess
    /// A `http(s)` reference; the app never fetches from the network.
    case remote
    case missing
}
