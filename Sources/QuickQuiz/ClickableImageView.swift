import AppKit

final class ClickableImageView: NSImageView {
    var onClick: (() -> Void)?
    var onMagnify: ((NSEvent) -> Void)?
    var onScrollWheel: ((NSEvent) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func magnify(with event: NSEvent) {
        if let onMagnify {
            onMagnify(event)
        } else {
            super.magnify(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if let onScrollWheel {
            onScrollWheel(event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}
