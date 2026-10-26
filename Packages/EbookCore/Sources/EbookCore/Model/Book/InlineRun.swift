/// A run of text sharing one set of inline styles.
public struct InlineRun: Sendable, Hashable {
    public var text: String
    public var isBold: Bool
    public var isItalic: Bool

    public init(_ text: String, bold: Bool = false, italic: Bool = false) {
        self.text = text
        self.isBold = bold
        self.isItalic = italic
    }
}
