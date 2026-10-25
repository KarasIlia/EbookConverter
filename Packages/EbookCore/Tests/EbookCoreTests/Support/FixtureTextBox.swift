import CoreGraphics

/// A single line of text drawn at `rect.origin` (page space, origin bottom-left) in a generated fixture PDF.
struct FixtureTextBox {
    var text: String
    var rect: CGRect
    var fontSize: Double
    var bold: Bool

    init(_ text: String, rect: CGRect, fontSize: Double = 12, bold: Bool = false) {
        self.text = text
        self.rect = rect
        self.fontSize = fontSize
        self.bold = bold
    }
}
