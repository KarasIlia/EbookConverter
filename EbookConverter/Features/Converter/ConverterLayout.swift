import CoreGraphics

/// Window sizes shared by the converter screens.
enum ConverterLayout {
    /// Minimum size of the compact screens: the drop zone and import progress.
    static let compactMinSize = CGSize(width: 480, height: 360)
    /// Minimum size of the loaded book workspace; the window grows to at least this when a book opens.
    static let workspaceMinSize = CGSize(width: 900, height: 600)
    /// Size the window grows to when a book opens, if the screen has room.
    static let workspaceIdealSize = CGSize(width: 1100, height: 700)
    /// Maximum width of the preview's text column, for comfortable line length.
    static let previewTextColumnWidth: CGFloat = 720
    /// Maximum width of the cover well in the inspector.
    static let coverWellWidth: CGFloat = 160
}
