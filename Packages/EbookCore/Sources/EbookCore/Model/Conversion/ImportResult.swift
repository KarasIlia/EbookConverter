public struct ImportResult: Sendable {
    public var document: BookDocument
    public var sourceCover: ImageAsset?
    public var warnings: [ImportWarning]
    /// The detected format of the imported file; set by `BookConverter`.
    public var sourceFormat: SourceFormat?

    public init(
        document: BookDocument, sourceCover: ImageAsset? = nil, warnings: [ImportWarning] = [], sourceFormat: SourceFormat? = nil
    ) {
        self.document = document
        self.sourceCover = sourceCover
        self.warnings = warnings
        self.sourceFormat = sourceFormat
    }
}
