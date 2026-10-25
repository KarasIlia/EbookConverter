import CoreGraphics

/// Window sizes shared by the converter screens.
enum ConverterLayout {
    /// Minimum size of the compact screens: the drop zone and import progress.
    static let compactMinSize = CGSize(width: 480, height: 360)
    /// Minimum size of the loaded book workspace. The window grows to it when a book opens:
    /// with `.windowResizability(.contentSize)` it follows the content's minimum, not its ideal size.
    static let workspaceMinSize = CGSize(width: 1100, height: 700)
    /// Maximum width of the preview's text column, for comfortable line length.
    static let previewTextColumnWidth: CGFloat = 720
}
