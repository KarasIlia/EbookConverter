import AppKit

/// Enlarges a window to a preferred content size when a book opens.
///
/// SwiftUI's `.windowResizability(.contentMinSize)` only enforces the content's minimum size, and
/// the content's ideal size is not applied to an existing window, so the window is grown here.
@MainActor enum WindowGrowth {
    /// Grows `window` so its content is at least `contentSize`, keeping the top-left corner where
    /// possible and the whole window inside the screen's visible area. Never shrinks the window.
    static func grow(_ window: NSWindow?, toContentSize contentSize: CGSize) {
        guard let window, let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let current = window.frame
        let wanted = window.frameRect(forContentRect: CGRect(origin: .zero, size: contentSize)).size
        let width = min(max(current.width, wanted.width), visible.width)
        let height = min(max(current.height, wanted.height), visible.height)
        guard width > current.width || height > current.height else { return }

        // AppKit's origin is the bottom-left corner: keep the top edge, then clamp into the screen.
        var frame = CGRect(x: current.minX, y: current.maxY - height, width: width, height: height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - height)
        window.setFrame(frame, display: true, animate: true)
    }
}
