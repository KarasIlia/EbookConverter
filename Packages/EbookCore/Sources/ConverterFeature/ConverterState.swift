import EbookCore

/// Lifecycle of the converter screen.
public enum ConverterState: Equatable {
    case empty
    case loading(fileName: String)
    case loaded
    case failed(ImportError)
}
