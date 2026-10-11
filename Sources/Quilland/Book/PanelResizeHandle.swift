import AppKit

/// A strip along the top edge of the bottom panel that drags it taller or shorter. The split view's own divider is one point thin and can be missed or covered;
/// this strip is wide enough to hit, shows the resize cursor, and a double-click gives the panel its usual height back.
final class PanelResizeHandle: NSView {
    /// Asks for the height the panel should have now.
    var onResize: ((CGFloat) -> Void)?
    var currentHeight: () -> CGFloat = { 0 }
    var onReset: (() -> Void)?
    private var startY: CGFloat = 0
    private var startHeight: CGFloat = 0

    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeUpDown) }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onReset?(); return }
        startY = event.locationInWindow.y
        startHeight = currentHeight()
    }
    override func mouseDragged(with event: NSEvent) {
        // Up (a larger y in the window) makes the panel taller.
        onResize?(startHeight + (event.locationInWindow.y - startY))
    }
    override var acceptsFirstResponder: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        // A faint grip in the middle of the strip.
        let grip = NSRect(x: bounds.midX - 18, y: bounds.midY - 1, width: 36, height: 2)
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(roundedRect: grip, xRadius: 1, yRadius: 1).fill()
    }
}
