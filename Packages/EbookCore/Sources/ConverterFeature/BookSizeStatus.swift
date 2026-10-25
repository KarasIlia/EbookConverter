/// Progress of measuring the output file.
public enum BookSizeStatus: Equatable, Sendable {
    case computing
    /// Exact size in bytes of the file `exportData()` produces.
    case ready(Int)
    /// Writing the book failed; export will fail too.
    case failed
}
