import AppKit

final class WindowDragHandleView: NSView {
    var canDrag: (() -> Bool)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard canDrag?() != false else { return }
        window?.performDrag(with: event)
    }
}
