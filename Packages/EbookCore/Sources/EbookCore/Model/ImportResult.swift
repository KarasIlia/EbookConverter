public struct ImportResult: Sendable {
    public var document: BookDocument
    public var sourceCover: ImageAsset?
    public var warnings: [ImportWarning]

    public init(document: BookDocument, sourceCover: ImageAsset? = nil, warnings: [ImportWarning] = []) {
        self.document = document
        self.sourceCover = sourceCover
        self.warnings = warnings
    }
}
