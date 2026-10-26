/// Errors of `ConverterViewModel.exportData()`.
public enum ExportError: Error, Equatable {
    /// No book is loaded.
    case noDocument
}
