/// A paragraph as produced by an importer, with the style signals used for heading detection.
public struct StyledParagraph: Sendable, Hashable {
    public var runs: [InlineRun]
    /// Dominant font size in points, if the source format has one.
    public var fontSize: Double?
    /// Explicit heading level from markup (Markdown `#`, HTML `<h1>`, Word heading style), 1 = top.
    public var headingLevelHint: Int?

    public init(runs: [InlineRun], fontSize: Double? = nil, headingLevelHint: Int? = nil) {
        self.runs = runs
        self.fontSize = fontSize
        self.headingLevelHint = headingLevelHint
    }

    /// Concatenated run text.
    public var text: String { runs.map(\.text).joined() }

    /// `true` when every run containing visible text is bold (and there is at least one).
    public var isAllBold: Bool {
        let visible = runs.filter { !$0.text.allSatisfy(\.isWhitespace) }
        return !visible.isEmpty && visible.allSatisfy(\.isBold)
    }
}
