import CoreGraphics

/// One visual line of text extracted from a PDF page.
public struct PDFTextLine: Sendable, Hashable {
    public var text: String
    public var runs: [InlineRun]
    public var pageIndex: Int
    /// Line rectangle in page space (origin bottom-left).
    public var bounds: CGRect
    /// Dominant font size of the line, in points.
    public var fontSize: Double
    public var pageSize: CGSize

    public init(text: String, runs: [InlineRun], pageIndex: Int, bounds: CGRect, fontSize: Double, pageSize: CGSize) {
        self.text = text
        self.runs = runs
        self.pageIndex = pageIndex
        self.bounds = bounds
        self.fontSize = fontSize
        self.pageSize = pageSize
    }
}
